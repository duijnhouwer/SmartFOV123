import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum ImmersiveSpaceState: Equatable {
        case closed
        case inTransition
        case open
    }

    enum TrialPhase: Equatable {
        case targetCue
        case search
    }

    let immersiveSpaceID = "MobiWordFinderSpace"
    let plan: ExperimentPlan?
    let stimulusPresentationState = StimulusPresentationState()
    private let feedbackSoundPlayer = FeedbackSoundPlayer()
    private let speechListener = SpeechConfirmationListener()
    private var speechRestartTask: Task<Void, Never>?
    private var instantiatedExperiment: Experiment?
    private(set) var currentTrialIndex = 0
    private(set) var completedTrialToken = 0
    private(set) var trialPhase: TrialPhase = .targetCue
    private(set) var hasConfigurationError = false
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var statusMessage: String?
    var recognizedSpeech: String?
    var isListening = false

    init() {
        do {
            plan = try ExperimentPlan.loadBundled()
        } catch {
            plan = nil
            hasConfigurationError = true
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
        if instantiatedExperiment != nil {
            trialPhase = .targetCue
            stimulusPresentationState.reset()
            return true
        }
        guard let plan, plan.trials.indices.contains(currentTrialIndex) else { return false }
        let scheduledTrial = plan.trials[currentTrialIndex]
        instantiatedExperiment = await Task.detached(priority: .userInitiated) {
            scheduledTrial.instantiate()
        }.value
        trialPhase = .targetCue
        stimulusPresentationState.reset()
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
            switch trialPhase {
            case .targetCue:
                statusMessage = "Listening… read the target number shown above the X grid."
            case .search:
                statusMessage = "Listening… find the target, then read the three crossing digits."
            }
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

        if candidate == experiment.grid.targetNumber {
            if trialPhase == .targetCue {
                trialPhase = .search
                stimulusPresentationState.revealGrid()
                statusMessage = "Target confirmed. Find it, then read the three crossing digits."
            }
            // Participants naturally repeat the target while searching. Treat
            // that as neither correct nor incorrect and start a clean speech
            // recognition pass without playing feedback.
            scheduleSpeechRestart(afterNanoseconds: 250_000_000)
        } else if trialPhase == .targetCue {
            statusMessage = "Heard \(candidate), but that isn't the target shown above the grid. Try again."
            feedbackSoundPlayer.playWrong()
            scheduleSpeechRestart(afterNanoseconds: 2_000_000_000)
        } else if candidate == experiment.grid.verificationCode {
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
        trialPhase = .targetCue
        stimulusPresentationState.reset()
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
