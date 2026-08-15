import AVFoundation
import Foundation
import Speech

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

    // A visionOS immersive-space transition can invalidate the RemoteIO proxy
    // owned by an AVAudioEngine. Reusing that engine then fails in start() with
    // "Session lookup failed". Give each recognition pass a fresh engine so it
    // always binds to the currently active audio session.
    private var audioEngine: AVAudioEngine?
    private static let audioSessionQueue = DispatchQueue(
        label: "SmartFOV123.AudioSession"
    )
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionID: UUID?
    private var hasInputTap = false

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
        onTranscription: @escaping (String) -> Void,
        onEnded: @escaping (Error?) -> Void
    ) async throws {
        stop()

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
            "yes", "no", "begin", "quit"
        ]
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        do {
            try await Self.configureAndActivateAudioSession()
        } catch {
            if sessionID == currentSessionID {
                sessionID = nil
            }
            throw error
        }
        guard sessionID == currentSessionID else {
            throw CancellationError()
        }

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            sessionID = nil
            stopAudioInput()
            Self.deactivateAudioSession()
            throw ListenerError.microphoneUnavailable
        }

        recognitionRequest = request

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasInputTap = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let transcript = result?.bestTranscription.formattedString {
                Task { @MainActor [weak self] in
                    guard self?.sessionID == currentSessionID else { return }
                    onTranscription(transcript)
                }
            }

            if result?.isFinal == true || error != nil {
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == currentSessionID else { return }
                    self.finishCurrentSession()
                    onEnded(error)
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        stopRecognitionAndAudioInput()
        Self.deactivateAudioSession()
    }

    /// Stops microphone capture but intentionally leaves the play-and-record
    /// session active long enough for head-locked feedback audio to play.
    func pauseForFeedback() {
        stopRecognitionAndAudioInput()
    }

    /// Stops capture and waits until all queued audio-session work has finished.
    /// Immersive spaces use this before dismissal so visionOS cannot tear down a
    /// scene while its microphone session is still being deactivated.
    func stopAndWaitForAudioSession() async {
        stopRecognitionAndAudioInput()
        await Self.deactivateAudioSessionAndWait()
    }

    private func stopRecognitionAndAudioInput() {
        sessionID = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        stopAudioInput()
    }

    private func finishCurrentSession() {
        sessionID = nil
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        stopAudioInput()
        Self.deactivateAudioSession()
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

    private static func deactivateAudioSession() {
        audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }

    private static func deactivateAudioSessionAndWait() async {
        await withCheckedContinuation { continuation in
            audioSessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
                continuation.resume()
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
