import AVFoundation
import Dispatch
import Foundation
import Speech

struct TimedSpeechSegment: Sendable {
    let id: String
    let text: String
    let startUptimeNanoseconds: UInt64
    let stopUptimeNanoseconds: UInt64
}

/// Routes the permanent microphone tap to whichever recognition request is
/// currently active. The audio-render callback isn't main-actor isolated, so
/// access to the request is protected independently.
private final class SpeechAudioBufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func route(to request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock {
            self.request = request
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            request?.append(buffer)
        }
    }
}

@MainActor
final class SpeechConfirmationListener {
    enum ListenerError: LocalizedError {
        case microphonePermissionDenied
        case speechPermissionDenied
        case recognizerUnavailable
        case microphoneUnavailable

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access is required to verify the crossing digits."
            case .speechPermissionDenied:
                return "Speech recognition access is required to verify the crossing digits."
            case .recognizerUnavailable:
                return "English speech recognition is currently unavailable."
            case .microphoneUnavailable:
                return "The microphone isn't currently available."
            }
        }
    }

    // The windowless app owns one persistent compositor scene, so its RemoteIO
    // proxy no longer changes between prompts or trials. Keep the audio session,
    // engine, and input tap alive for the whole experiment. Repeatedly tearing
    // them down caused proxy-session lookup failures and clipped recognition.
    private var audioEngine: AVAudioEngine?
    private static let audioSessionQueue = DispatchQueue(
        label: "SmartFOV123.AudioSession"
    )
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let audioBufferSink = SpeechAudioBufferSink()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionID: UUID?
    private var hasInputTap = false
    private var isAudioSessionConfigured = false
    private var recognitionPassNumber: UInt64 = 0

    static func requestAuthorization() async throws {
        async let microphoneGranted = requestMicrophoneAuthorization()
        async let speechStatus = requestSpeechAuthorization()

        guard await microphoneGranted else {
            throw ListenerError.microphonePermissionDenied
        }
        guard await speechStatus == .authorized else {
            throw ListenerError.speechPermissionDenied
        }
    }

    func start(
        onTranscription: @escaping (String, [TimedSpeechSegment]) -> Void,
        onEnded: @escaping (Error?) -> Void
    ) async throws {
        stopRecognitionPass()
        recognitionPassNumber &+= 1
        let pass = recognitionPassNumber
        DiagnosticLog.event("speech", "listener pass \(pass) begin; recognizerAvailable=\(recognizer?.isAvailable ?? false)")

        guard let recognizer, recognizer.isAvailable else {
            throw ListenerError.recognizerUnavailable
        }

        let currentSessionID = UUID()
        sessionID = currentSessionID

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        request.contextualStrings = [
            "zero", "one", "two", "three", "four",
            "five", "six", "seven", "eight", "nine",
            "yes", "no", "begin", "stop"
        ]
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        if !isAudioSessionConfigured {
            DiagnosticLog.event("audio", "pass \(pass) activating AVAudioSession")
            do {
                try await Self.configureAndActivateAudioSession()
                isAudioSessionConfigured = true
                DiagnosticLog.event("audio", "pass \(pass) AVAudioSession active")
            } catch {
                if sessionID == currentSessionID {
                    sessionID = nil
                }
                throw error
            }
        }
        guard sessionID == currentSessionID else {
            throw CancellationError()
        }

        do {
            try ensureAudioInputIsRunning()
        } catch {
            sessionID = nil
            stopAudioInput()
            throw error
        }

        recognitionRequest = request
        let recognitionStartUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        audioBufferSink.route(to: request)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let transcription = result?.bestTranscription {
                let segments = transcription.segments.enumerated().map { index, segment in
                    let startOffset = UInt64(max(0, segment.timestamp) * 1_000_000_000)
                    let stopOffset = UInt64(max(0, segment.timestamp + segment.duration) * 1_000_000_000)
                    return TimedSpeechSegment(
                        id: "\(pass)-\(index)",
                        text: segment.substring,
                        startUptimeNanoseconds: recognitionStartUptimeNanoseconds + startOffset,
                        stopUptimeNanoseconds: recognitionStartUptimeNanoseconds + stopOffset
                    )
                }
                Task { @MainActor [weak self] in
                    guard self?.sessionID == currentSessionID else { return }
                    onTranscription(transcription.formattedString, segments)
                }
            }

            if result?.isFinal == true || error != nil {
                DiagnosticLog.event("speech", "listener callback ended; pass=\(pass) final=\(result?.isFinal == true) error=\(error?.localizedDescription ?? "none")")
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == currentSessionID else { return }
                    self.finishRecognitionPass()
                    onEnded(error)
                }
            }
        }

    }

    func stop() {
        stopRecognitionPass()
    }

    /// Releases microphone and audio-session resources before visionOS
    /// suspends the app. Normal trial-to-trial stops intentionally keep the
    /// audio graph alive, so background cleanup needs a stronger operation.
    func prepareForBackground() {
        DiagnosticLog.event("audio", "background audio teardown begin")
        stopRecognitionPass()
        stopAudioInput()
        isAudioSessionConfigured = false
        Self.audioSessionQueue.async {
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
                DiagnosticLog.event("audio", "background AVAudioSession deactivated")
            } catch {
                print(
                    "SmartFOV123 audio error while entering background: "
                        + error.localizedDescription
                )
            }
        }
    }

    /// Stops routing microphone buffers into speech recognition while leaving
    /// the permanent audio graph active for uninterrupted feedback and restart.
    func pauseForFeedback() {
        stopRecognitionPass()
    }

    private func stopRecognitionPass() {
        sessionID = nil
        audioBufferSink.route(to: nil)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    private func finishRecognitionPass() {
        sessionID = nil
        audioBufferSink.route(to: nil)
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    private func ensureAudioInputIsRunning() throws {
        if let audioEngine {
            guard !audioEngine.isRunning else {
                DiagnosticLog.event("audio", "reusing running AVAudioEngine")
                return
            }
            audioEngine.prepare()
            try audioEngine.start()
            DiagnosticLog.event("audio", "existing AVAudioEngine restarted")
            return
        }

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        DiagnosticLog.event("audio", "creating AVAudioEngine; sampleRate=\(format.sampleRate) channels=\(format.channelCount)")
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw ListenerError.microphoneUnavailable
        }

        let sink = audioBufferSink
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            sink.append(buffer)
        }
        hasInputTap = true
        self.audioEngine = audioEngine
        audioEngine.prepare()
        try audioEngine.start()
        DiagnosticLog.event("audio", "new AVAudioEngine started and input tap installed")
    }

    private func stopAudioInput() {
        guard let audioEngine else {
            hasInputTap = false
            return
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        audioEngine.reset()
        self.audioEngine = nil
    }

    private static func configureAndActivateAudioSession() async throws {
        try await withCheckedThrowingContinuation { continuation in
            audioSessionQueue.async {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(
                        .playAndRecord,
                        mode: .measurement,
                        options: .duckOthers
                    )
                    try audioSession.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
