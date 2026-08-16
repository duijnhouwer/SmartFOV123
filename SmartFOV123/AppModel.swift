import Dispatch
import Darwin
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppModel {
    enum ImmersiveSpaceState: Equatable {
        case closed
        case inTransition
        case open
    }

    enum TrialPhase: Equatable {
        case configurationError
        case participantNumber
        case participantConfirmation
        case instructions
        case debriefing
        case transitioning
        case targetCue
        case search
    }

    struct ParticipantPrompt: Equatable {
        let title: String
        let message: String
        let emphasizedText: String?
    }

    let immersiveSpaceID = "SmartFOV123Space"
    let plan: ExperimentPlan?
    let stimulusPresentationState = StimulusPresentationState()
    private let feedbackSoundPlayer = FeedbackSoundPlayer()
    private let resultFileWriter = ResultFileWriter()
    private let speechListener = SpeechConfirmationListener()
    private let appStartUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var speechRestartTask: Task<Void, Never>?
    private var backgroundObserverTask: Task<Void, Never>?
    private var instantiatedExperiment: Experiment?
    private var preparedTrialRevision: Int?
    private var currentTrialMeasurement: InProgressTrialMeasurement?
    private var pendingSubjectNumber: String?
    private var isRetryingSubjectNumber = false
    private var hasExperimentBegun = false
    private var hasStartedWindowlessExperience = false
    private var isAdvancingCompletedTrial = false
    private(set) var currentTrialIndex = 0
    private(set) var completedTrialToken = 0
    private(set) var beginExperimentToken = 0
    private(set) var immersivePresentationGeneration = 0
    private(set) var subjectNumber: String?
    private(set) var trialPhase: TrialPhase = .participantNumber
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var statusMessage: String?
    var isListening = false

    init() {
        do {
            plan = try ExperimentPlan.loadBundled()
        } catch {
            plan = nil
            trialPhase = .configurationError
            statusMessage = error.localizedDescription
            print("SmartFOV123 configuration error: \(error.localizedDescription)")
        }
    }

    var experiment: Experiment? {
        instantiatedExperiment
    }

    var showsParticipantInterface: Bool {
        switch trialPhase {
        case .configurationError, .participantNumber, .participantConfirmation, .instructions, .debriefing:
            return true
        case .transitioning, .targetCue, .search:
            return false
        }
    }

    var showsStimulus: Bool {
        trialPhase == .targetCue || trialPhase == .search
    }

    /// Keeps the persistent compositor renderer prepared during the opening
    /// dialogs, but prevents it from rebuilding against stale trial data while
    /// trials transition or after the experiment ends.
    var shouldRunStimulusRenderer: Bool {
        stimulusPresentationState.content != .hidden
    }

    var trialCount: Int {
        plan?.trials.count ?? 0
    }

    var hasCompletedExperiment: Bool {
        plan != nil && currentTrialIndex >= trialCount
    }

    var participantPrompt: ParticipantPrompt? {
        switch trialPhase {
        case .configurationError:
            return .init(
                title: "Configuration Error",
                message: "\(statusMessage ?? "The experiment configuration is invalid.")\n\nPress the Digital Crown to leave SmartFOV123.",
                emphasizedText: nil
            )
        case .participantNumber:
            let digitCount = plan?.subjectNumberDigitCount ?? 3
            return .init(
                title: isRetryingSubjectNumber ? "Please try again" : "Welcome!",
                message: isRetryingSubjectNumber
                    ? "Please state your \(digitCount)-digit number, one digit at a time."
                    : "Please state your \(digitCount)-digit participant number.",
                emphasizedText: nil
            )
        case .participantConfirmation:
            guard let pendingSubjectNumber else { return nil }
            return .init(
                title: pendingSubjectNumber,
                message: "Did I hear that correctly?\n\nSay “Yes” or “No”.",
                emphasizedText: nil
            )
        case .instructions:
            guard let plan else { return nil }
            return .init(
                title: "Instructions",
                message: "\(plan.instructions)\n\nReady to start?\nSpeak: “Begin”",
                emphasizedText: nil
            )
        case .debriefing:
            guard let plan else { return nil }
            return .init(
                title: "Experiment Complete",
                message: plan.debriefing,
                emphasizedText: nil
            )
        case .transitioning, .targetCue, .search:
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
        if let instantiatedExperiment {
            preparedTrialRevision = stimulusPresentationState.prepareTrial(
                experiment: instantiatedExperiment,
                trialsRemaining: max(0, trialCount - currentTrialIndex)
            )
        }
        return true
    }

    func prepareImmersivePresentation() {
        if plan == nil {
            trialPhase = .configurationError
            stimulusPresentationState.hide()
        } else if hasCompletedExperiment {
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
        synchronizeParticipantPresentation()
    }

    func markCurrentTrialStartedIfReady() {
        guard hasExperimentBegun, trialPhase == .targetCue else { return }
        markCurrentTrialStarted()
    }

    func beginImmersivePresentation() {
        immersivePresentationGeneration += 1
    }

    func beginTrialTransition() {
        beginImmersivePresentation()
        trialPhase = .transitioning
        stimulusPresentationState.hide()
    }

    func presentPreparedTrial() {
        beginImmersivePresentation()
        trialPhase = .targetCue
        stimulusPresentationState.reset()
    }

    func showConfigurationError(_ message: String) {
        beginImmersivePresentation()
        statusMessage = message
        trialPhase = .configurationError
        stimulusPresentationState.hide()
        synchronizeParticipantPresentation()
    }

    func startWindowlessExperienceIfNeeded() {
        guard !hasStartedWindowlessExperience else { return }
        hasStartedWindowlessExperience = true
        backgroundObserverTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didEnterBackgroundNotification
            ) {
                guard let self else { return }
                self.terminateWhenBackgrounded()
            }
        }
        Task { @MainActor [weak self] in
            await self?.startWindowlessExperience()
        }
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

    private func startWindowlessExperience() async {
        immersiveSpaceState = .inTransition

        if plan != nil, !(await prepareCurrentTrial()) {
            showConfigurationError("No scheduled trial is available.")
        } else {
            prepareImmersivePresentation()
            beginImmersivePresentation()
        }

        guard await requestSpeechAuthorization() else {
            showConfigurationError(
                statusMessage ?? "Microphone and speech-recognition access are required."
            )
            immersiveSpaceState = .open
            return
        }

        immersiveSpaceState = .open
        await waitForRendererToStart()
        await startSpeechConfirmation()
    }

    private func waitForRendererToStart() async {
        let timeout = ContinuousClock.now.advanced(by: .seconds(2))
        while !stimulusPresentationState.isRendererRunning,
              ContinuousClock.now < timeout {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func markCurrentTrialStarted() {
        currentTrialMeasurement = .init(startTimeMS: elapsedMilliseconds())
    }

    func startSpeechConfirmation() async {
        speechRestartTask?.cancel()
        speechRestartTask = nil

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
            case .configurationError:
                statusMessage = statusMessage ?? "The experiment configuration is invalid."
            case .participantNumber:
                statusMessage = "Listening for the three-digit participant number."
            case .participantConfirmation:
                statusMessage = "Listening for yes or no."
            case .instructions:
                statusMessage = "Listening for begin."
            case .debriefing:
                statusMessage = "Debriefing displayed."
            case .transitioning:
                statusMessage = "Preparing the next trial…"
            case .targetCue:
                statusMessage = "Listening… read the target number shown above the X grid."
            case .search:
                statusMessage = "Listening… find the target, then read the three crossing digits."
            }
            await feedbackSoundPlayer.prepare()
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

        if trialPhase == .configurationError || trialPhase == .debriefing {
            return
        }

        guard let experiment else { return }
        switch trialPhase {
        case .configurationError:
            return
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
        case .transitioning:
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
                print("SmartFOV123 result error: trial timing record is incomplete.")
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
                scheduleCompletedTrialAdvance()
            } catch {
                statusMessage = "Correct response, but trial \(currentTrialIndex + 1) couldn't be saved: \(error.localizedDescription) Say the crossing sequence again to retry."
                print("SmartFOV123 result error: \(error.localizedDescription)")
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
        preparedTrialRevision = nil
        currentTrialMeasurement = nil
        if hasCompletedExperiment {
            trialPhase = .debriefing
            stimulusPresentationState.hide()
            synchronizeParticipantPresentation()
            if let fileURL = resultFileWriter.fileURL {
                statusMessage = "Experiment complete — all \(trialCount) trials finished. Results: Results/\(fileURL.lastPathComponent)"
            } else {
                statusMessage = "Experiment complete — all \(trialCount) trials finished."
            }
        } else if plan.trials.indices.contains(currentTrialIndex) {
            let trial = plan.trials[currentTrialIndex]
            statusMessage = "Preparing trial \(trial.trialNumber) of \(trialCount) (\(trial.conditionName))."
        }
    }

    private func handleRecognitionEnded(_ error: Error?) {
        guard immersiveSpaceState == .open else { return }
        isListening = false
        if let error {
            statusMessage = "Speech recognition paused: \(error.localizedDescription) Retrying…"
        } else if trialPhase == .configurationError {
            statusMessage = "The experiment configuration is invalid."
        } else if trialPhase == .participantConfirmation {
            statusMessage = "I didn't catch yes or no. Listening again…"
        } else if trialPhase == .instructions {
            statusMessage = "I didn't catch begin. Listening again…"
        } else if trialPhase == .debriefing {
            statusMessage = "Debriefing displayed."
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
        synchronizeParticipantPresentation()
        speechListener.stop()
        isListening = false
        scheduleSpeechRestart(afterNanoseconds: 250_000_000)
    }

    private func handleParticipantConfirmation(_ transcript: String) {
        let words = transcript
            .lowercased()
            .split { !$0.isLetter }
            .map(String.init)

        if words.contains("yes"), let pendingSubjectNumber {
            subjectNumber = pendingSubjectNumber
            self.pendingSubjectNumber = nil
            trialPhase = .instructions
            synchronizeParticipantPresentation()
            speechListener.stop()
            isListening = false
            scheduleSpeechRestart(afterNanoseconds: 250_000_000)
            return
        }

        pendingSubjectNumber = nil
        isRetryingSubjectNumber = true
        trialPhase = .participantNumber
        synchronizeParticipantPresentation()
        speechListener.stop()
        isListening = false
        scheduleSpeechRestart(afterNanoseconds: 250_000_000)
    }

    private func handleInstructionsResponse(_ transcript: String) {
        let words = transcript
            .lowercased()
            .split { !$0.isLetter }
            .map(String.init)

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
        trialPhase = .transitioning
        stimulusPresentationState.hide()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.stopSpeechConfirmation()
            await self.waitForPreparedTrialResources()
            self.beginImmersivePresentation()
            self.trialPhase = .targetCue
            self.stimulusPresentationState.reset()
            self.beginExperimentToken += 1
            self.markCurrentTrialStartedIfReady()
            await self.startSpeechConfirmation()
        }
    }

    private func synchronizeParticipantPresentation() {
        guard showsParticipantInterface, let prompt = participantPrompt else { return }
        stimulusPresentationState.showParticipantPrompt(
            .init(
                title: prompt.title,
                message: prompt.message,
                emphasizedText: prompt.emphasizedText,
                usesLeadingAlignment: trialPhase == .instructions
            )
        )
    }

    private func scheduleCompletedTrialAdvance() {
        Task { @MainActor [weak self] in
            await self?.advanceCompletedTrialInPersistentSpace()
        }
    }

    private func advanceCompletedTrialInPersistentSpace() async {
        guard !isAdvancingCompletedTrial,
              immersiveSpaceState == .open else { return }
        isAdvancingCompletedTrial = true
        defer { isAdvancingCompletedTrial = false }

        await stopSpeechConfirmation()

        let finishesExperiment = currentTrialIndex + 1 >= trialCount
        if !finishesExperiment {
            beginTrialTransition()
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        advanceAfterCompletedTrial()
        if hasCompletedExperiment {
            await startSpeechConfirmation()
            return
        }

        guard await prepareCurrentTrial() else {
            showConfigurationError("The next scheduled trial couldn't be prepared.")
            await startSpeechConfirmation()
            return
        }

        await waitForPreparedTrialResources()
        presentPreparedTrial()
        markCurrentTrialStartedIfReady()
        await startSpeechConfirmation()
    }

    private func waitForPreparedTrialResources() async {
        guard let preparedTrialRevision else { return }
        while !stimulusPresentationState.isTrialReady(revision: preparedTrialRevision) {
            guard immersiveSpaceState == .open || immersiveSpaceState == .inTransition else { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// The Digital Crown returns the windowless experience to Home View,
    /// which backgrounds the research app. End the session at that point.
    private func terminateWhenBackgrounded() -> Never {
        speechListener.stop()
        isListening = false
        speechRestartTask?.cancel()
        stimulusPresentationState.hide()
        exit(EXIT_SUCCESS)
    }

}

private struct InProgressTrialMeasurement {
    let startTimeMS: UInt64
    var digitRevealMS: UInt64?
    var speech: [CompletedTrialResults.SpeechDetection] = []
}
