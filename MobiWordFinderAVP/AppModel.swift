import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum ImmersiveSpaceState: Equatable {
        case closed
        case inTransition
        case open
    }

    let immersiveSpaceID = "MobiWordFinderSpace"
    let experiment: Experiment?
    private let feedbackSoundPlayer = FeedbackSoundPlayer()
    private let speechListener = SpeechConfirmationListener()
    private var speechRestartTask: Task<Void, Never>?
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var statusMessage: String?
    var recognizedSpeech: String?
    var isListening = false

    init() {
        do {
            experiment = try Experiment.loadBundled()
        } catch {
            experiment = nil
            statusMessage = error.localizedDescription
            print("MobiWordFinder configuration error: \(error.localizedDescription)")
        }
    }

    var trialDescription: String {
        guard let experiment else { return "No valid experiment is loaded." }
        return "Find \(experiment.grid.targetNumber) in the \(experiment.grid.columns) × \(experiment.grid.rows) grid. Then read the three digits crossing its middle digit, one digit at a time."
    }

    func requestSpeechAuthorization() async -> Bool {
        do {
            try await SpeechConfirmationListener.requestAuthorization()
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func startSpeechConfirmation() async {
        speechRestartTask?.cancel()
        speechRestartTask = nil
        recognizedSpeech = nil

        do {
            try await speechListener.start(
                onTranscription: { [weak self] transcript in
                    self?.handleTranscript(transcript)
                },
                onEnded: { [weak self] error in
                    self?.handleRecognitionEnded(error)
                }
            )
            isListening = true
            statusMessage = "Listening… read the three crossing digits one at a time."
        } catch {
            isListening = false
            statusMessage = "Speech recognition couldn't start: \(error.localizedDescription)"
        }
    }

    func stopSpeechConfirmation() {
        speechRestartTask?.cancel()
        speechRestartTask = nil
        speechListener.stop()
        isListening = false
    }

    private func handleTranscript(_ transcript: String) {
        guard immersiveSpaceState == .open,
              let experiment else { return }

        recognizedSpeech = transcript
        guard let candidate = SpokenDigitParser.parseThreeDigits(
            from: transcript,
            aliases: experiment.configuration.speech.aliasLookup
        ) else {
            return
        }

        speechListener.stop()
        isListening = false
        if candidate == experiment.grid.verificationCode {
            statusMessage = "Correct — heard \(candidate)."
            feedbackSoundPlayer.playCorrect()
        } else {
            statusMessage = "Heard \(candidate), but that isn't the crossing sequence. Try again."
            feedbackSoundPlayer.playWrong()
            scheduleSpeechRestart(afterNanoseconds: 2_000_000_000)
        }
    }

    private func handleRecognitionEnded(_ error: Error?) {
        guard immersiveSpaceState == .open else { return }
        isListening = false
        if let error {
            statusMessage = "Speech recognition paused: \(error.localizedDescription) Retrying…"
        } else {
            statusMessage = "I didn't catch three digits. Listening again…"
        }
        scheduleSpeechRestart(afterNanoseconds: 500_000_000)
    }

    private func scheduleSpeechRestart(afterNanoseconds delay: UInt64) {
        speechRestartTask?.cancel()
        speechRestartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled,
                  let self,
                  self.immersiveSpaceState == .open else { return }
            await self.startSpeechConfirmation()
        }
    }
}
