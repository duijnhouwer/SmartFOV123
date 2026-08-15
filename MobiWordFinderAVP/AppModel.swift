import Dispatch
import Darwin
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
        case participantNumber
        case participantConfirmation
        case instructions
        case debriefing
        case targetCue
        case search
    }

    struct ParticipantPrompt: Equatable {
        let title: String
        let message: String
        let emphasizedText: String?
    }

    let immersiveSpaceID = "MobiWordFinderSpace"
    let participantSpaceID = "MobiWordFinderParticipantSpace"
    let plan: ExperimentPlan?
    let stimulusPresentationState = StimulusPresentationState()
    private let feedbackSoundPlayer = FeedbackSoundPlayer()
    private let resultFileWriter = ResultFileWriter()
    private let speechListener = SpeechConfirmationListener()
    private let appStartUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var speechRestartTask: Task<Void, Never>?
    private var instantiatedExperiment: Experiment?
    private var currentTrialMeasurement: InProgressTrialMeasurement?
    private var pendingSubjectNumber: String?
    private var isRetryingSubjectNumber = false
    private var hasExperimentBegun = false
    private(set) var currentTrialIndex = 0
    private(set) var completedTrialToken = 0
    private(set) var beginExperimentToken = 0
    private(set) var immersivePresentationGeneration = 0
    private(set) var subjectNumber: String?
    private(set) var trialPhase: TrialPhase = .participantNumber
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

    var activeImmersiveSpaceID: String {
        switch trialPhase {
        case .participantNumber, .participantConfirmation, .instructions, .debriefing:
            participantSpaceID
        case .targetCue, .search:
            immersiveSpaceID
        }
    }

    var trialCount: Int {
        plan?.trials.count ?? 0
    }

    var hasCompletedExperiment: Bool {
        plan != nil && currentTrialIndex >= trialCount
    }

    var trialDescription: String {
        if subjectNumber == nil {
            return "Ready to collect the participant number before trial 1."
        }
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

    var participantPrompt: ParticipantPrompt? {
        switch trialPhase {
        case .participantNumber:
            let digitCount = plan?.subjectNumberDigitCount ?? 3
            return .init(
                title: isRetryingSubjectNumber ? "Please try again" : "Welcome!",
                message: isRetryingSubjectNumber
                    ? "Please state your \(digitCount)-digit number, one digit at a time.\n\nSpeak “Quit” to exit."
                    : "Please state your \(digitCount)-digit participant number.\n\nSpeak “Quit” to exit.",
                emphasizedText: nil
            )
        case .participantConfirmation:
            guard let pendingSubjectNumber else { return nil }
            return .init(
                title: "The number you said was:",
                message: "Is that correct?\nSpeak: “Yes”, “No”, or “Quit”",
                emphasizedText: pendingSubjectNumber
            )
        case .instructions:
            guard let plan else { return nil }
            return .init(
                title: "Instructions",
                message: "\(plan.instructions)\n\nReady to start?\nSpeak: “Begin” or “Quit”",
                emphasizedText: nil
            )
        case .debriefing:
            guard let plan else { return nil }
            return .init(
                title: "Experiment Complete",
                message: plan.debriefing,
                emphasizedText: nil
            )
        case .targetCue, .search:
            return nil
        }
    }

    @discardableResult
    func prepareCurrentTrial() async -> Bool {
        if instantiatedExperiment != nil {
            return true
        }
        guard let plan, plan.trials.indices.contains(currentTrialIndex) else { return false }
        let scheduledTrial = plan.trials[currentTrialIndex]
        instantiatedExperiment = await Task.detached(priority: .userInitiated) {
            scheduledTrial.instantiate()
        }.value
        return true
    }

    func prepareImmersivePresentation() {
        if hasCompletedExperiment {
            trialPhase = .debriefing
            stimulusPresentationState.hide()
        } else if !hasExperimentBegun, subjectNumber == nil {
            pendingSubjectNumber = nil
            isRetryingSubjectNumber = false
            trialPhase = .participantNumber
            stimulusPresentationState.hide()
        } else if !hasExperimentBegun {
            trialPhase = .instructions
            stimulusPresentationState.hide()
        } else {
            trialPhase = .targetCue
            stimulusPresentationState.reset()
        }
    }

    func markCurrentTrialStartedIfReady() {
        guard hasExperimentBegun, trialPhase == .targetCue else { return }
        markCurrentTrialStarted()
    }

    func beginImmersivePresentation() {
        immersivePresentationGeneration += 1
    }

    func publishImmersiveSpaceState(
        _ state: ImmersiveSpaceState,
        generation: Int
    ) {
        guard generation == immersivePresentationGeneration else { return }
        immersiveSpaceState = state
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

    func markCurrentTrialStarted() {
        currentTrialMeasurement = .init(startTimeMS: elapsedMilliseconds())
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
            case .participantNumber:
                statusMessage = "Listening for the three-digit participant number."
            case .participantConfirmation:
                statusMessage = "Listening for yes, no, or quit."
            case .instructions:
                statusMessage = "Listening for begin or quit."
            case .debriefing:
                statusMessage = "Debriefing displayed. Listening for quit."
            case .targetCue:
                statusMessage = "Listening… read the target number shown above the X grid."
            case .search:
                statusMessage = "Listening… find the target, then read the three crossing digits."
            }
        } catch {
            isListening = false
            if error is CancellationError {
                return
            }
            statusMessage = "Speech recognition couldn't start: \(error.localizedDescription) Retrying…"
            if immersiveSpaceState == .open {
                scheduleSpeechRestart(afterNanoseconds: 1_000_000_000)
            }
        }
    }

    func stopSpeechConfirmation() async {
        speechRestartTask?.cancel()
        speechRestartTask = nil
        await speechListener.stopAndWaitForAudioSession()
        isListening = false
    }

    private func handleTranscript(_ transcript: String) {
        guard immersiveSpaceState == .open else { return }

        recognizedSpeech = transcript
        if trialPhase == .debriefing {
            handleDebriefingResponse(transcript)
            return
        }

        guard let experiment else { return }
        switch trialPhase {
        case .participantNumber:
            handleParticipantNumber(transcript, experiment: experiment)
            return
        case .participantConfirmation:
            handleParticipantConfirmation(transcript)
            return
        case .instructions:
            handleInstructionsResponse(transcript)
            return
        case .debriefing:
            return
        case .targetCue, .search:
            break
        }

        guard let candidate = SpokenDigitParser.parseThreeDigits(
            from: transcript,
            aliases: experiment.configuration.speech.aliasLookup
        ) else {
            return
        }
        currentTrialMeasurement?.speech.append(
            .init(
                utterance: SpokenDigitParser.normalizedForStorage(
                    transcript,
                    aliases: experiment.configuration.speech.aliasLookup
                ),
                ms: elapsedMilliseconds()
            )
        )

        speechListener.pauseForFeedback()
        isListening = false

        if candidate == experiment.grid.targetNumber {
            if trialPhase == .targetCue {
                trialPhase = .search
                currentTrialMeasurement?.digitRevealMS = elapsedMilliseconds()
                stimulusPresentationState.revealGrid()
                feedbackSoundPlayer.playPop()
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
            guard let measurement = currentTrialMeasurement,
                  let digitRevealMS = measurement.digitRevealMS else {
                statusMessage = "Correct response, but the trial timing record is incomplete."
                print("MobiWordFinder result error: trial timing record is incomplete.")
                return
            }
            let targetFoundMS = elapsedMilliseconds()
            feedbackSoundPlayer.playCorrect()
            do {
                try resultFileWriter.appendCompletedTrial(
                    experiment,
                    results: .init(
                        startTimeMS: measurement.startTimeMS,
                        digitRevealMS: digitRevealMS,
                        targetFoundMS: targetFoundMS,
                        speech: measurement.speech
                    )
                )
                statusMessage = "Correct — heard \(candidate)."
                completedTrialToken += 1
            } catch {
                statusMessage = "Correct response, but trial \(currentTrialIndex + 1) couldn't be saved: \(error.localizedDescription) Say the crossing sequence again to retry."
                print("MobiWordFinder result error: \(error.localizedDescription)")
                scheduleSpeechRestart(afterNanoseconds: 2_000_000_000)
            }
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
        currentTrialMeasurement = nil
        stimulusPresentationState.reset()
        if hasCompletedExperiment {
            trialPhase = .debriefing
            stimulusPresentationState.hide()
            if let fileURL = resultFileWriter.fileURL {
                statusMessage = "Experiment complete — all \(trialCount) trials finished. Results: Results/\(fileURL.lastPathComponent)"
            } else {
                statusMessage = "Experiment complete — all \(trialCount) trials finished."
            }
        } else if plan.trials.indices.contains(currentTrialIndex) {
            trialPhase = .targetCue
            let trial = plan.trials[currentTrialIndex]
            statusMessage = "Ready for trial \(trial.trialNumber) of \(trialCount) (\(trial.conditionName))."
        }
    }

    private func handleRecognitionEnded(_ error: Error?) {
        guard immersiveSpaceState == .open else { return }
        isListening = false
        if let error {
            statusMessage = "Speech recognition paused: \(error.localizedDescription) Retrying…"
        } else if trialPhase == .participantConfirmation {
            statusMessage = "I didn't catch yes, no, or quit. Listening again…"
        } else if trialPhase == .instructions {
            statusMessage = "I didn't catch begin or quit. Listening again…"
        } else if trialPhase == .debriefing {
            statusMessage = "I didn't catch quit. Listening again…"
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

    private func elapsedMilliseconds() -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= appStartUptimeNanoseconds else { return 0 }
        return (now - appStartUptimeNanoseconds) / 1_000_000
    }

    private func handleParticipantNumber(_ transcript: String, experiment: Experiment) {
        let words = transcript
            .lowercased()
            .split { !$0.isLetter }
            .map(String.init)

        if words.contains("quit") {
            terminateResearchApplication()
        }

        guard let plan,
              let candidate = SpokenDigitParser.parseDigits(
            from: transcript,
            aliases: experiment.configuration.speech.aliasLookup,
            digitCount: plan.subjectNumberDigitCount
        ) else {
            return
        }

        pendingSubjectNumber = candidate
        isRetryingSubjectNumber = false
        trialPhase = .participantConfirmation
        speechListener.stop()
        isListening = false
        scheduleSpeechRestart(afterNanoseconds: 250_000_000)
    }

    private func handleParticipantConfirmation(_ transcript: String) {
        let words = transcript
            .lowercased()
            .split { !$0.isLetter }
            .map(String.init)

        if words.contains("quit") {
            terminateResearchApplication()
        }

        if words.contains("yes"), let pendingSubjectNumber {
            subjectNumber = pendingSubjectNumber
            self.pendingSubjectNumber = nil
            trialPhase = .instructions
            speechListener.stop()
            isListening = false
            scheduleSpeechRestart(afterNanoseconds: 250_000_000)
            return
        }

        pendingSubjectNumber = nil
        isRetryingSubjectNumber = true
        trialPhase = .participantNumber
        speechListener.stop()
        isListening = false
        scheduleSpeechRestart(afterNanoseconds: 250_000_000)
    }

    private func handleInstructionsResponse(_ transcript: String) {
        let words = transcript
            .lowercased()
            .split { !$0.isLetter }
            .map(String.init)

        if words.contains("quit") {
            terminateResearchApplication()
        }
        guard words.contains("begin"), let subjectNumber, let plan else {
            return
        }

        resultFileWriter.beginExperiment(
            protocolName: plan.protocolName,
            subjectNumber: subjectNumber
        )
        hasExperimentBegun = true
        speechListener.stop()
        isListening = false
        trialPhase = .targetCue
        stimulusPresentationState.reset()
        beginExperimentToken += 1
    }

    private func handleDebriefingResponse(_ transcript: String) {
        let words = transcript
            .lowercased()
            .split { !$0.isLetter }
            .map(String.init)

        if words.contains("quit") {
            terminateResearchApplication()
        }
    }

    func terminateResearchApplication() -> Never {
        speechListener.stop()
        isListening = false
        speechRestartTask?.cancel()
        stimulusPresentationState.hide()

        // Apple intentionally doesn't provide a supported API for a visionOS
        // app to terminate itself, and calling exit() is not considered good
        // platform style or appropriate behavior for an App Store app.
        //
        // MobiWordFinderAVP is a privately deployed research application. Its
        // spoken “Quit” command has an explicit experimental requirement to
        // end the entire process, so we deliberately use exit() here instead
        // of merely dismissing the app's windows and immersive space.
        exit(EXIT_SUCCESS)
    }

}

private struct InProgressTrialMeasurement {
    let startTimeMS: UInt64
    var digitRevealMS: UInt64?
    var speech: [CompletedTrialResults.SpeechDetection] = []
}
