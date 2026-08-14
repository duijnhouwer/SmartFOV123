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
    let plan: ExperimentPlan?
    private let feedbackSoundPlayer = FeedbackSoundPlayer()
    private let speechListener = SpeechConfirmationListener()
    private var speechRestartTask: Task<Void, Never>?
    private var instantiatedExperiment: Experiment?
    private(set) var currentTrialIndex = 0
    private(set) var completedTrialToken = 0
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var statusMessage: String?
    var recognizedSpeech: String?
    var isListening = false

    init() {
        do {
            plan = try ExperimentPlan.loadBundled()
        } catch {
            plan = nil
            statusMessage = error.localizedDescription
            print("MobiWordFinder configuration error: \(error.localizedDescription)")
        }
    }

    var experiment: Experiment? {
        instantiatedExperiment
    }

    var trialCount: Int {
        plan?.trials.count ?? 0
    }

    var hasCompletedExperiment: Bool {
        plan != nil && currentTrialIndex >= trialCount
    }

    var trialDescription: String {
        if hasCompletedExperiment {
            return "Experiment complete — all \(trialCount) trials have been confirmed."
        }
        guard let plan, plan.trials.indices.contains(currentTrialIndex) else {
            return "No valid experiment is loaded."
        }
        let trial = plan.trials[currentTrialIndex]
        if let experiment {
            return "Trial \(trial.trialNumber) of \(trialCount), \(trial.conditionName): find \(experiment.grid.targetNumber) in the \(experiment.grid.columns) × \(experiment.grid.rows) grid. Then read the three digits crossing its middle digit, one digit at a time."
        }
        return "Trial \(trial.trialNumber) of \(trialCount), \(trial.conditionName). The target and grid will be generated when the trial starts."
    }

    @discardableResult
    func prepareCurrentTrial() async -> Bool {
        if instantiatedExperiment != nil { return true }
        guard let plan, plan.trials.indices.contains(currentTrialIndex) else { return false }
        let scheduledTrial = plan.trials[currentTrialIndex]
        instantiatedExperiment = await Task.detached(priority: .userInitiated) {
            scheduledTrial.instantiate()
        }.value
        return true
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
            completedTrialToken += 1
        } else {
            statusMessage = "Heard \(candidate), but that isn't the crossing sequence. Try again."
            feedbackSoundPlayer.playWrong()
            scheduleSpeechRestart(afterNanoseconds: 2_000_000_000)
        }
    }

    func advanceAfterCompletedTrial() {
        guard let plan, currentTrialIndex < plan.trials.count else { return }
        currentTrialIndex += 1
        instantiatedExperiment = nil
        if hasCompletedExperiment {
            statusMessage = "Experiment complete — all \(trialCount) trials finished."
        } else if plan.trials.indices.contains(currentTrialIndex) {
            let trial = plan.trials[currentTrialIndex]
            statusMessage = "Ready for trial \(trial.trialNumber) of \(trialCount) (\(trial.conditionName))."
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
