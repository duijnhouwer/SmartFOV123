import Dispatch
import Darwin
import Observation
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
        case protocolSelection
        case keyboardUnavailable
        case participantNumber
        case participantConfirmation
        case instructions
        case debriefing
        case transitioning
        case targetCue
        case search
    }

    let immersiveSpaceID = "SmartFOV123Space"
    private let availablePlans: [ExperimentPlan]
    private let invalidProtocols: [ProtocolCatalog.InvalidProtocol]
    let foveatedRendering: Bool
    private(set) var plan: ExperimentPlan?
    let stimulusPresentationState = StimulusPresentationState()
    private let feedbackSoundPlayer = FeedbackSoundPlayer()
    private let countdownAudioPlayer = CountdownAudioPlayer()
    private let resultFileWriter = ResultFileWriter()
    private let speechListener = SpeechConfirmationListener()
    @ObservationIgnored
    private lazy var keyboardInputListener = KeyboardInputListener { [weak self] key in
        self?.handleExperimentKey(key)
    }
    private let appStartUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var speechRestartTask: Task<Void, Never>?
    private var postStopMaskTask: Task<Void, Never>?
    private var keyboardDigits = ""
    private var backgroundObserverTask: Task<Void, Never>?
    private var sceneDeactivationObserverTask: Task<Void, Never>?
    private var sceneActivationObserverTask: Task<Void, Never>?
    private var foregroundObserverTask: Task<Void, Never>?
    private var timedSessionTask: Task<Void, Never>?
    private var timedSessionElapsedNanoseconds: UInt64 = 0
    private var timedSessionSearchStartNanoseconds: UInt64?
    private var timedSessionFinalSound: SoundEffectConfiguration?
    private var instantiatedExperiment: Experiment?
    private var preparedTrialRevision: Int?
    private var currentTrialMeasurement: InProgressTrialMeasurement?
    private var pendingSubjectNumber: String?
    private var isRetryingSubjectNumber = false
    private var hasExperimentBegun = false
    private var hasStartedWindowlessExperience = false
    private var isAdvancingCompletedTrial = false
    private var hasTimedSessionEnded = false
    private var forcedVoiceInput = false
    private(set) var currentTrialIndex = 0
    private(set) var completedTargetCount = 0
    private(set) var subjectNumber: String?
    private(set) var trialPhase: TrialPhase = .participantNumber
    private var configuredPassthroughDimming: Double = 0
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var statusMessage: String?

    init() {
        DiagnosticLog.event("app", "AppModel initialization started")
        do {
            let catalog = try ProtocolCatalog.loadAvailable()
            availablePlans = catalog.plans
            invalidProtocols = catalog.invalidProtocols
            foveatedRendering = catalog.foveatedRendering
            plan = nil
            trialPhase = .protocolSelection
            DiagnosticLog.event("app", "protocol catalog loaded; plans=\(catalog.plans.count) invalid=\(catalog.invalidProtocols.count) foveated=\(catalog.foveatedRendering)")
        } catch {
            availablePlans = []
            invalidProtocols = []
            foveatedRendering = true
            plan = nil
            trialPhase = .configurationError
            statusMessage = error.localizedDescription
            print("SmartFOV123 configuration error: \(error.localizedDescription)")
            DiagnosticLog.event("error", "configuration load failed: \(error.localizedDescription)")
        }
    }

    var experiment: Experiment? {
        instantiatedExperiment
    }

    var passthroughDimming: Double {
        switch trialPhase {
        case .transitioning, .targetCue, .search:
            return configuredPassthroughDimming
        case .configurationError, .protocolSelection, .keyboardUnavailable, .participantNumber,
             .participantConfirmation, .instructions, .debriefing:
            return 0
        }
    }

    var trialCount: Int {
        plan?.trials.count ?? 0
    }

    var hasCompletedExperiment: Bool {
        guard let plan else { return false }
        switch plan.taskMode {
        case .fixedNumberOfTrials:
            return currentTrialIndex >= trialCount
        case .loopTrials:
            return hasTimedSessionEnded
        }
    }

    var participantPrompt: StimulusPresentationState.Prompt? {
        switch trialPhase {
        case .configurationError:
            return .init(
                title: "Configuration Error",
                message: "\(statusMessage ?? "The experiment configuration is invalid.")\n\nPress the Digital Crown to leave SmartFOV123.",
                usesLeadingAlignment: false
            )
        case .protocolSelection:
            let validNames = availablePlans.enumerated().map {
                "\($0.offset + 1). \($0.element.protocolName)"
            }.joined(separator: "\n")
            let invalidNames = invalidProtocols.enumerated().map {
                "\(availablePlans.count + $0.offset + 1). \($0.element.filename)"
            }.joined(separator: "\n")
            var sections: [String] = []
            if !validNames.isEmpty {
                sections.append(validNames)
            }
            if !invalidNames.isEmpty {
                sections.append(
                    "The following protocols are present in the protocol folder but not valid:\n\(invalidNames)"
                )
            }
            return .init(
                title: "SmartFOV123",
                message: "\(sections.joined(separator: "\n\n"))\n\nSpeak number of protocol to inspect or run",
                usesLeadingAlignment: true
            )
        case .keyboardUnavailable:
            return .init(
                title: "Keyboard Required",
                message: "The protocol calls for keyboard input, but no hardware keyboard is connected. Please exit, connect an Apple Magic Keyboard or another compatible hardware keyboard, and try again. Or continue with voice override.\n\nPress the Digital Crown to exit,\nor speak “Continue with voice”.",
                usesLeadingAlignment: false
            )
        case .participantNumber:
            let digitCount = plan?.subjectNumberDigitCount ?? 3
            return .init(
                title: isRetryingSubjectNumber ? "Please try again" : "Welcome!",
                message: isRetryingSubjectNumber
                    ? "Please state your \(digitCount)-digit number, one digit at a time."
                    : "Please state your \(digitCount)-digit participant number.",
                usesLeadingAlignment: false
            )
        case .participantConfirmation:
            guard let pendingSubjectNumber else { return nil }
            return .init(
                title: pendingSubjectNumber,
                message: "Did I hear that correctly?\n\nSay “Yes” or “No”.",
                usesLeadingAlignment: false
            )
        case .instructions:
            guard let plan else { return nil }
            return .init(
                title: "Instructions",
                message: "\(plan.instructions)\n\nReady to start?\nSpeak: “Begin”",
                usesLeadingAlignment: true
            )
        case .debriefing:
            guard let plan else { return nil }
            let message = plan.debriefing.replacingOccurrences(
                of: "<NUMBER_OF_TARGETS_FOUND>",
                with: String(completedTargetCount)
            )
            return .init(
                title: plan.debriefingTitle,
                message: message,
                usesLeadingAlignment: false
            )
        case .transitioning, .targetCue, .search:
            return nil
        }
    }

    @discardableResult
    func prepareCurrentTrial() async -> Bool {
        if instantiatedExperiment != nil {
            DiagnosticLog.event("trial", "prepare skipped; trial \(currentTrialIndex + 1) already instantiated")
            return true
        }
        guard let plan, !plan.trials.isEmpty else { return false }
        let scheduledIndex: Int
        switch plan.taskMode {
        case .fixedNumberOfTrials:
            guard plan.trials.indices.contains(currentTrialIndex) else { return false }
            scheduledIndex = currentTrialIndex
        case .loopTrials:
            scheduledIndex = currentTrialIndex % plan.trials.count
        }
        let scheduledTrial = plan.trials[scheduledIndex]
        let trialNumber = currentTrialIndex + 1
        DiagnosticLog.event("trial", "prepare begin; trial=\(trialNumber) scheduleIndex=\(scheduledIndex) condition=\(scheduledTrial.conditionNumber)")
        instantiatedExperiment = await Task.detached(priority: .userInitiated) {
            scheduledTrial.instantiate(trialNumber: trialNumber)
        }.value
        if let instantiatedExperiment {
            configuredPassthroughDimming = instantiatedExperiment.configuration.display.passthroughDimming
            print(
                "SmartFOV123 trial \(trialNumber) passthrough dimming: \(configuredPassthroughDimming)"
            )
            DiagnosticLog.event("trial", "instantiated trial=\(trialNumber) dimming=\(configuredPassthroughDimming)")
        }
        if hasCompletedExperiment {
            instantiatedExperiment = nil
            return true
        }
        if let instantiatedExperiment {
            preparedTrialRevision = stimulusPresentationState.prepareTrial(
                experiment: instantiatedExperiment,
                taskMode: plan.taskMode,
                score: completedTargetCount,
                trialsRemaining: max(0, trialCount - currentTrialIndex)
            )
            DiagnosticLog.event("trial", "resource request published; trial=\(trialNumber) revision=\(preparedTrialRevision ?? -1)")
        }
        return true
    }

    func prepareImmersivePresentation() {
        if plan == nil, availablePlans.isEmpty, invalidProtocols.isEmpty {
            trialPhase = .configurationError
            stimulusPresentationState.hide()
        } else if plan == nil {
            trialPhase = .protocolSelection
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

    func beginTrialTransition() {
        trialPhase = .transitioning
    }

    func presentPreparedTrial() {
        trialPhase = .targetCue
        stimulusPresentationState.reset()
    }

    func showConfigurationError(_ message: String) {
        postStopMaskTask?.cancel()
        postStopMaskTask = nil
        speechRestartTask?.cancel()
        speechRestartTask = nil
        speechListener.stop()
        statusMessage = message
        trialPhase = .configurationError
        stimulusPresentationState.hide()
        synchronizeParticipantPresentation()
    }

    func startWindowlessExperienceIfNeeded() {
        guard !hasStartedWindowlessExperience else { return }
        hasStartedWindowlessExperience = true
        DiagnosticLog.event("lifecycle", "windowless experience starting")
        backgroundObserverTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didEnterBackgroundNotification
            ) {
                guard let self else { return }
                DiagnosticLog.event("lifecycle", "UIApplication.didEnterBackground received")
                self.terminateWhenBackgrounded()
            }
        }
        sceneDeactivationObserverTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIScene.willDeactivateNotification
            ) {
                guard self != nil else { return }
                DiagnosticLog.event("lifecycle", "UIScene.willDeactivate received")
            }
        }
        foregroundObserverTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIScene.willEnterForegroundNotification
            ) {
                guard self != nil else { return }
                DiagnosticLog.event("lifecycle", "UIScene.willEnterForeground received")
            }
        }
        sceneActivationObserverTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIScene.didActivateNotification
            ) {
                guard self != nil else { return }
                DiagnosticLog.event("lifecycle", "UIScene.didActivate received")
            }
        }
        Task { @MainActor [weak self] in
            await self?.startWindowlessExperience()
        }
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
        DiagnosticLog.event("app", "immersive startup begin")
        keyboardInputListener.start()
        immersiveSpaceState = .inTransition

        if plan != nil, !(await prepareCurrentTrial()) {
            showConfigurationError("No scheduled trial is available.")
        } else {
            prepareImmersivePresentation()
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
        DiagnosticLog.event("app", "immersive startup ready; rendererRunning=\(stimulusPresentationState.isRendererRunning)")
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
        postStopMaskTask?.cancel()
        postStopMaskTask = nil
        currentTrialMeasurement = .init(absoluteTrialStartMS: elapsedMilliseconds())
        DiagnosticLog.event("trial", "measurement started; trial=\(currentTrialIndex + 1) phase=\(String(describing: trialPhase))")
    }

    func startSpeechConfirmation() async {
        speechRestartTask?.cancel()
        speechRestartTask = nil
        guard trialPhase != .configurationError, trialPhase != .debriefing,
              shouldUseSpeech(in: trialPhase) else { return }
        DiagnosticLog.event("speech", "recognition start requested; trial=\(currentTrialIndex + 1) phase=\(String(describing: trialPhase))")

        do {
            try await speechListener.start(
                onTranscription: { [weak self] transcript, segments in
                    self?.handleTranscript(transcript, segments: segments)
                },
                onEnded: { [weak self] error in
                    self?.handleRecognitionEnded(error)
                }
            )
            DiagnosticLog.event("speech", "recognition started; trial=\(currentTrialIndex + 1) phase=\(String(describing: trialPhase))")
            switch trialPhase {
            case .protocolSelection:
                statusMessage = "Listening for a protocol number."
            case .keyboardUnavailable:
                statusMessage = "Say “Continue with voice” to override keyboard input."
            case .participantNumber:
                let digitCount = plan?.subjectNumberDigitCount ?? 3
                statusMessage = "Listening for the \(digitCount)-digit participant number."
            case .participantConfirmation:
                statusMessage = "Listening for yes or no."
            case .instructions:
                statusMessage = "Listening for begin."
            case .configurationError, .debriefing:
                return
            case .transitioning:
                statusMessage = "Preparing the next trial…"
            case .targetCue:
                statusMessage = "Listening… read the target number shown above the X grid."
            case .search:
                statusMessage = "Listening… find the target, then read the three crossing digits."
            }
            if let plan {
                await feedbackSoundPlayer.prepare(configuration: plan.sounds)
            }
        } catch {
            if error is CancellationError {
                return
            }
            statusMessage = "Speech recognition couldn't start: \(error.localizedDescription) Retrying…"
            DiagnosticLog.event("error", "recognition start failed: \(error.localizedDescription)")
            if immersiveSpaceState == .open {
                scheduleSpeechRestart(afterNanoseconds: 1_000_000_000)
            }
        }
    }

    func stopSpeechConfirmation() {
        speechRestartTask?.cancel()
        speechRestartTask = nil
        speechListener.stop()
    }

    private func handleTranscript(
        _ transcript: String,
        segments: [TimedSpeechSegment] = []
    ) {
        guard immersiveSpaceState == .open else { return }

        if trialPhase == .protocolSelection {
            handleProtocolSelection(transcript)
            return
        }
        if trialPhase == .keyboardUnavailable {
            handleVoiceInputOverride(transcript)
            return
        }
        guard experiment != nil else { return }
        switch trialPhase {
        case .configurationError, .protocolSelection, .keyboardUnavailable,
             .debriefing, .transitioning:
            return
        case .participantNumber:
            handleParticipantNumber(transcript)
            return
        case .participantConfirmation:
            handleParticipantConfirmation(transcript)
            return
        case .instructions:
            handleInstructionsResponse(transcript)
            return
        case .targetCue, .search:
            break
        }

        guard let plan else { return }
        let speech = plan.input.speech
        mergeSpeechSegments(segments, aliases: speech.aliasLookup)

        if trialPhase == .search,
           plan.input.stopCommand == .speechStop,
           let stopSegment = segments.first(where: {
               $0.text.lowercased().split(whereSeparator: { !$0.isLetter }).contains("stop")
           }) {
            stopSearchTimer(atMS: elapsedMilliseconds(atUptimeNanoseconds: stopSegment.startUptimeNanoseconds))
            speechListener.pauseForFeedback()
            scheduleSpeechRestart(afterNanoseconds: 250_000_000)
            return
        }
        if trialPhase == .targetCue, plan.input.startDigits != .speech { return }
        if trialPhase == .search, plan.input.crossDigits != .speech { return }

        let attemptDigits = currentSpeechDigitAttempt(
            from: segments,
            aliases: speech.aliasLookup,
            maximumPauseSeconds: speech.maxInterdigitPauseSeconds
        )
        let candidate = String(attemptDigits.map(\.digit))
        guard candidate.count == 3 else {
            return
        }
        DiagnosticLog.event("speech", "three-digit candidate parsed; trial=\(currentTrialIndex + 1) phase=\(String(describing: trialPhase)) candidate=\(candidate)")
        handleTrialCandidate(candidate, spoken: true)
    }

    private func handleTrialCandidate(_ candidate: String, spoken: Bool) {
        guard let experiment else { return }
        if spoken { speechListener.pauseForFeedback() }
        if trialPhase == .targetCue {
            if candidate == experiment.grid.targetNumber {
                trialPhase = .search
                let targetReadMS = elapsedMilliseconds()
                currentTrialMeasurement?.digitRevealMS = targetReadMS
                currentTrialMeasurement?.timerStartMS = targetReadMS
                resultFileWriter.markFirstTargetRead(atMS: targetReadMS)
                startTimedSessionIfNeeded()
                DiagnosticLog.event("trial", "target cue confirmed; trial=\(currentTrialIndex + 1); search phase entered")
                stimulusPresentationState.revealGrid()
                feedbackSoundPlayer.playReveal()
                statusMessage = "Target confirmed. Find it, then read the three crossing digits."
                scheduleSpeechRestart(afterNanoseconds: 250_000_000)
            } else {
                statusMessage = "\(spoken ? "Heard" : "Entered") \(candidate), but that isn't the target shown above the grid. Try again."
                feedbackSoundPlayer.playWrong()
                scheduleSpeechRestart(afterNanoseconds: 2_000_000_000)
            }
            return
        }

        let answerCorrect = candidate == experiment.grid.verificationCode
        guard let measurement = currentTrialMeasurement,
              let digitRevealMS = measurement.digitRevealMS,
              let timerStartMS = measurement.timerStartMS,
              let stopSignalStartMS = measurement.stopSignalStartMS,
              let timerStopMS = measurement.timerStopMS else {
            statusMessage = "Use the configured stop command before entering the crossing number."
            scheduleSpeechRestart(afterNanoseconds: 250_000_000)
            return
        }
        if answerCorrect {
            feedbackSoundPlayer.playCorrect()
        } else {
            feedbackSoundPlayer.playWrong()
        }
        do {
            try resultFileWriter.appendCompletedTrial(
                experiment,
                results: .init(
                    absoluteTrialStartMS: measurement.absoluteTrialStartMS,
                    digitRevealMS: digitRevealMS,
                    timerStartMS: timerStartMS,
                    stopSignalStartMS: stopSignalStartMS,
                    timerStopMS: timerStopMS,
                    answerCorrect: answerCorrect,
                    speech: measurement.speech,
                    keyboard: measurement.keyboard
                )
            )
            if answerCorrect { completedTargetCount += 1 }
            DiagnosticLog.event("result", "trial saved; trial=\(currentTrialIndex + 1) correct=\(answerCorrect) score=\(completedTargetCount) stopSignalMS=\(stopSignalStartMS)")
            statusMessage = "\(answerCorrect ? "Correct" : "Incorrect") — \(spoken ? "heard" : "entered") \(candidate)."
            let highlightEnabled = answerCorrect
                ? experiment.configuration.stimulus.digitHighlightCorrectRGB != nil
                : experiment.configuration.stimulus.digitHighlightWrongRGB != nil
            if highlightEnabled {
                stimulusPresentationState.highlightSolution(correct: answerCorrect)
            }
            trialPhase = .transitioning
            scheduleCompletedTrialAdvance()
        } catch {
            statusMessage = "Response received, but trial \(currentTrialIndex + 1) couldn't be saved: \(error.localizedDescription)"
            print("SmartFOV123 result error: \(error.localizedDescription)")
            scheduleSpeechRestart(afterNanoseconds: 2_000_000_000)
        }
    }

    private func shouldUseSpeech(in phase: TrialPhase) -> Bool {
        guard let plan else { return true }
        switch phase {
        case .targetCue:
            return plan.input.startDigits == .speech
        case .search:
            return plan.input.stopCommand == .speechStop || plan.input.crossDigits == .speech
        default:
            return true
        }
    }

    private func handleExperimentKey(_ key: ExperimentKey) {
        guard let plan, immersiveSpaceState == .open else { return }
        let eventMS = elapsedMilliseconds()
        if trialPhase == .targetCue || trialPhase == .search {
            currentTrialMeasurement?.keyboard.append(.init(key: key.logName, startMS: Int64(eventMS)))
        }
        switch key {
        case .space where trialPhase == .search && plan.input.stopCommand == .keyboardSpace:
            stopSearchTimer(atMS: eventMS)
        case .digit(let digit) where trialPhase == .targetCue && plan.input.startDigits == .keyboard:
            collectKeyboardDigit(digit)
        case .digit(let digit) where trialPhase == .search && plan.input.crossDigits == .keyboard:
            collectKeyboardDigit(digit)
        case .delete where acceptsKeyboardDigits:
            if !keyboardDigits.isEmpty { keyboardDigits.removeLast() }
        case .enter where acceptsKeyboardDigits:
            submitKeyboardDigits()
        default:
            break
        }
    }

    private func collectKeyboardDigit(_ digit: Character) {
        guard keyboardDigits.count < 3 else { return }
        keyboardDigits.append(digit)
    }

    private var acceptsKeyboardDigits: Bool {
        guard let plan else { return false }
        return (trialPhase == .targetCue && plan.input.startDigits == .keyboard)
            || (trialPhase == .search && plan.input.crossDigits == .keyboard)
    }

    private func submitKeyboardDigits() {
        guard keyboardDigits.count == 3 else { return }
        let candidate = keyboardDigits
        keyboardDigits = ""
        handleTrialCandidate(candidate, spoken: false)
    }

    private func stopSearchTimer(atMS milliseconds: UInt64) {
        guard trialPhase == .search,
              currentTrialMeasurement?.stopSignalStartMS == nil else { return }
        currentTrialMeasurement?.stopSignalStartMS = milliseconds
        pauseTimedSession()
        currentTrialMeasurement?.timerStopMS = elapsedMilliseconds()
        feedbackSoundPlayer.playStopTimer()
        schedulePostStopMask(
            afterSeconds: instantiatedExperiment?.configuration.stimulus.postStopVisibilitySeconds ?? 0
        )
        statusMessage = "Timer stopped. Enter the three crossing digits."
    }

    private func schedulePostStopMask(afterSeconds visibilitySeconds: Float) {
        postStopMaskTask?.cancel()
        let visibilityNanoseconds = UInt64(Double(visibilitySeconds) * 1_000_000_000)
        guard visibilityNanoseconds > 0 else {
            stimulusPresentationState.maskGrid()
            return
        }
        postStopMaskTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: visibilityNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  self.trialPhase == .search,
                  self.currentTrialMeasurement?.stopSignalStartMS != nil else { return }
            self.stimulusPresentationState.maskGrid()
        }
    }

    func advanceAfterCompletedTrial() {
        postStopMaskTask?.cancel()
        postStopMaskTask = nil
        guard let plan, !hasTimedSessionEnded else { return }
        if plan.taskMode == .fixedNumberOfTrials,
           currentTrialIndex >= plan.trials.count {
            return
        }
        currentTrialIndex += 1
        instantiatedExperiment = nil
        preparedTrialRevision = nil
        currentTrialMeasurement = nil
        if hasCompletedExperiment {
            trialPhase = .debriefing
            stimulusPresentationState.hide()
            synchronizeParticipantPresentation()
            do {
                try resultFileWriter.finishFixedExperiment(endTimeMS: elapsedMilliseconds())
            } catch {
                statusMessage = "Experiment complete, but the result couldn't be saved: \(error.localizedDescription)"
                print("SmartFOV123 result error: \(error.localizedDescription)")
                return
            }
            if let fileURL = resultFileWriter.fileURL {
                statusMessage = "Experiment complete — all \(trialCount) trials finished. Results: Results/\(fileURL.lastPathComponent)"
            } else {
                statusMessage = "Experiment complete — all \(trialCount) trials finished."
            }
        } else {
            switch plan.taskMode {
            case .fixedNumberOfTrials:
                let trial = plan.trials[currentTrialIndex]
                statusMessage = "Preparing trial \(trial.trialNumber) of \(trialCount) (condition \(trial.conditionNumber))."
            case .loopTrials:
                let trial = plan.trials[currentTrialIndex % plan.trials.count]
                statusMessage = "Preparing target \(currentTrialIndex + 1) (score \(completedTargetCount), condition \(trial.conditionNumber))."
            }
        }
    }

    private func handleRecognitionEnded(_ error: Error?) {
        guard immersiveSpaceState == .open else { return }
        guard trialPhase != .configurationError, trialPhase != .debriefing else { return }
        DiagnosticLog.event("speech", "recognition ended; phase=\(String(describing: trialPhase)) error=\(error?.localizedDescription ?? "none")")
        if let error {
            statusMessage = "Speech recognition paused: \(error.localizedDescription) Retrying…"
        } else if trialPhase == .protocolSelection {
            statusMessage = "I didn't catch a protocol number. Listening again…"
        } else if trialPhase == .keyboardUnavailable {
            statusMessage = "I didn't catch “Continue with voice”. Listening again…"
        } else if trialPhase == .participantConfirmation {
            statusMessage = "I didn't catch yes or no. Listening again…"
        } else if trialPhase == .instructions {
            statusMessage = "I didn't catch begin. Listening again…"
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
        elapsedMilliseconds(atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }

    private func elapsedMilliseconds(atUptimeNanoseconds uptime: UInt64) -> UInt64 {
        guard uptime >= appStartUptimeNanoseconds else { return 0 }
        return (uptime - appStartUptimeNanoseconds) / 1_000_000
    }

    private func mergeSpeechSegments(
        _ segments: [TimedSpeechSegment],
        aliases: [String: Int]
    ) {
        guard currentTrialMeasurement != nil else { return }
        let recognitionPasses = Dictionary(grouping: segments, by: \.recognitionPass)
        currentTrialMeasurement?.speech.removeAll { event in
            recognitionPasses.keys.contains { event.id.hasPrefix("\($0)-") }
        }
        for (pass, passSegments) in recognitionPasses {
            let ordered = passSegments.sorted {
                $0.startUptimeNanoseconds < $1.startUptimeNanoseconds
            }
            guard let first = ordered.first else { continue }
            let transcript = ordered.map(\.text).joined(separator: " ")
            let token = SpokenDigitParser.normalizedForStorage(
                transcript,
                aliases: aliases
            )
            currentTrialMeasurement?.speech.append(
                .init(
                    id: "\(pass)-utterance",
                    token: token,
                    startMS: Int64(elapsedMilliseconds(
                        atUptimeNanoseconds: first.startUptimeNanoseconds
                    ))
                )
            )
        }
        currentTrialMeasurement?.speech.sort { $0.startMS < $1.startMS }
    }

    private struct TimedDigit {
        let digit: Character
        let startUptimeNanoseconds: UInt64
        let stopUptimeNanoseconds: UInt64
    }

    private func currentSpeechDigitAttempt(
        from segments: [TimedSpeechSegment],
        aliases: [String: Int],
        maximumPauseSeconds: Float
    ) -> [TimedDigit] {
        let digits = segments.flatMap { segment -> [TimedDigit] in
            let normalized = SpokenDigitParser.normalizedForStorage(
                segment.text,
                aliases: aliases
            )
            guard !normalized.isEmpty,
                  normalized.allSatisfy(\.isNumber) else {
                return []
            }
            let characters = Array(normalized)
            let duration = segment.stopUptimeNanoseconds >= segment.startUptimeNanoseconds
                ? segment.stopUptimeNanoseconds - segment.startUptimeNanoseconds
                : 0
            return characters.enumerated().map { index, digit in
                .init(
                    digit: digit,
                    startUptimeNanoseconds: segment.startUptimeNanoseconds
                        + duration * UInt64(index) / UInt64(characters.count),
                    stopUptimeNanoseconds: segment.startUptimeNanoseconds
                        + duration * UInt64(index + 1) / UInt64(characters.count)
                )
            }
        }.sorted { $0.startUptimeNanoseconds < $1.startUptimeNanoseconds }

        let maximumPauseNanoseconds = UInt64(Double(maximumPauseSeconds) * 1_000_000_000)
        return digits.reduce(into: []) { attempt, digit in
            guard let previous = attempt.last else {
                attempt.append(digit)
                return
            }
            let pause = digit.startUptimeNanoseconds > previous.stopUptimeNanoseconds
                ? digit.startUptimeNanoseconds - previous.stopUptimeNanoseconds
                : 0
            if pause > maximumPauseNanoseconds {
                attempt = [digit]
            } else {
                attempt.append(digit)
            }
        }
    }

    private func handleParticipantNumber(_ transcript: String) {
        guard let plan,
              let candidate = SpokenDigitParser.parseDigits(
            from: transcript,
            aliases: plan.input.speech.aliasLookup,
            digitCount: plan.subjectNumberDigitCount
        ) else {
            return
        }

        pendingSubjectNumber = candidate
        isRetryingSubjectNumber = false
        trialPhase = .participantConfirmation
        synchronizeParticipantPresentation()
        speechListener.stop()
        scheduleSpeechRestart(afterNanoseconds: 250_000_000)
    }

    private func handleProtocolSelection(_ transcript: String) {
        guard let selection = Self.spokenProtocolNumber(transcript) else { return }
        if selection > availablePlans.count {
            let invalidIndex = selection - availablePlans.count - 1
            guard invalidProtocols.indices.contains(invalidIndex) else { return }
            let invalid = invalidProtocols[invalidIndex]
            showConfigurationError("\(invalid.filename)\n\n\(invalid.errorMessage)")
            return
        }
        guard availablePlans.indices.contains(selection - 1) else { return }
        let selected = availablePlans[selection - 1]

        plan = selected
        forcedVoiceInput = false
        statusMessage = "Selected protocol \(selected.protocolName)."
        speechListener.stop()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.prepareCurrentTrial() else {
                self.showConfigurationError("The selected protocol has no scheduled trial.")
                return
            }
            if selected.input.usesKeyboard,
               !KeyboardInputListener.isHardwareKeyboardConnected {
                self.trialPhase = .keyboardUnavailable
                self.statusMessage = "No hardware keyboard is connected."
            } else {
                self.trialPhase = .participantNumber
            }
            self.synchronizeParticipantPresentation()
            await self.startSpeechConfirmation()
        }
    }

    private func handleVoiceInputOverride(_ transcript: String) {
        let words = Set(transcript.lowercased().split { !$0.isLetter }.map(String.init))
        guard words.contains("continue"), words.contains("voice"), let plan else { return }

        self.plan = plan.replacingInput(with: plan.input.replacingModesWithVoiceOnly())
        forcedVoiceInput = true
        statusMessage = "Continuing with voice input for all controls."
        trialPhase = .participantNumber
        synchronizeParticipantPresentation()
        speechListener.stop()
        scheduleSpeechRestart(afterNanoseconds: 250_000_000)
    }

    private static func normalizedProtocolSelection(_ value: String) -> String {
        value.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .filter { $0 != "protocol" && $0 != "number" }
            .joined(separator: " ")
    }

    private static func spokenProtocolNumber(_ transcript: String) -> Int? {
        let normalized = normalizedProtocolSelection(transcript)
        if let number = Int(normalized) {
            return number
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .spellOut
        return availableSpokenNumberRange.first { number in
            guard let words = formatter.string(from: NSNumber(value: number)) else { return false }
            return normalizedProtocolSelection(words) == normalized
        }
    }

    private static let availableSpokenNumberRange = 1...999

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
            scheduleSpeechRestart(afterNanoseconds: 250_000_000)
            return
        }

        pendingSubjectNumber = nil
        isRetryingSubjectNumber = true
        trialPhase = .participantNumber
        synchronizeParticipantPresentation()
        speechListener.stop()
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
            subjectNumber: subjectNumber,
            taskMode: plan.taskMode,
            input: plan.input,
            sounds: plan.sounds,
            forcedVoiceInput: forcedVoiceInput
        )
        hasExperimentBegun = true
        speechListener.stop()
        trialPhase = .transitioning
        stimulusPresentationState.hide()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stopSpeechConfirmation()
            await self.waitForPreparedTrialResources()
            self.trialPhase = .targetCue
            self.stimulusPresentationState.reset()
            self.markCurrentTrialStartedIfReady()
            await self.startSpeechConfirmation()
        }
    }

    private func synchronizeParticipantPresentation() {
        guard let participantPrompt else { return }
        stimulusPresentationState.showParticipantPrompt(participantPrompt)
    }

    private func scheduleCompletedTrialAdvance() {
        DiagnosticLog.event("trial", "advance scheduled; completed trial=\(currentTrialIndex + 1)")
        Task { @MainActor [weak self] in
            await self?.advanceCompletedTrialInPersistentSpace()
        }
    }

    private func advanceCompletedTrialInPersistentSpace() async {
        guard !isAdvancingCompletedTrial,
              immersiveSpaceState == .open else { return }
        isAdvancingCompletedTrial = true
        DiagnosticLog.event("trial", "advance begin; completed trial=\(currentTrialIndex + 1)")
        defer { isAdvancingCompletedTrial = false }

        stopSpeechConfirmation()

        let finishesExperiment = plan?.taskMode == .fixedNumberOfTrials
            && currentTrialIndex + 1 >= trialCount
        if !finishesExperiment {
            beginTrialTransition()
        }

        advanceAfterCompletedTrial()
        if hasCompletedExperiment {
            return
        }

        guard await prepareCurrentTrial() else {
            showConfigurationError("The next scheduled trial couldn't be prepared.")
            return
        }

        await waitForPreparedTrialResources()
        guard !hasCompletedExperiment else { return }
        presentPreparedTrial()
        markCurrentTrialStartedIfReady()
        DiagnosticLog.event("trial", "advance complete; active trial=\(currentTrialIndex + 1)")
        await startSpeechConfirmation()
    }

    private func waitForPreparedTrialResources() async {
        guard let preparedTrialRevision else { return }
        DiagnosticLog.event("render", "waiting for resources; revision=\(preparedTrialRevision)")
        while !stimulusPresentationState.isTrialReady(revision: preparedTrialRevision) {
            guard immersiveSpaceState == .open || immersiveSpaceState == .inTransition else { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        DiagnosticLog.event("render", "resource wait ended; revision=\(preparedTrialRevision) ready=\(stimulusPresentationState.isTrialReady(revision: preparedTrialRevision))")
    }

    private func startTimedSessionIfNeeded() {
        guard let plan,
              case .loopTrials(let seconds) = plan.taskMode,
              hasExperimentBegun,
              trialPhase == .targetCue || trialPhase == .search,
              timedSessionSearchStartNanoseconds == nil,
              !hasTimedSessionEnded else { return }

        let durationNanoseconds = UInt64(seconds) * 1_000_000_000
        let remainingNanoseconds = durationNanoseconds > timedSessionElapsedNanoseconds
            ? durationNanoseconds - timedSessionElapsedNanoseconds
            : 0
        guard remainingNanoseconds > 0 else {
            finishTimedSession(durationSeconds: seconds)
            return
        }
        timedSessionSearchStartNanoseconds = DispatchTime.now().uptimeNanoseconds
        DiagnosticLog.event("session", "timed session resumed; durationSeconds=\(seconds) elapsedNanoseconds=\(timedSessionElapsedNanoseconds)")
        stimulusPresentationState.startTimeBar(
            durationSeconds: seconds,
            elapsedNanoseconds: timedSessionElapsedNanoseconds
        )
        timedSessionFinalSound = plan.sounds.final
        countdownAudioPlayer.start(sound: plan.sounds.timer)
        timedSessionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: remainingNanoseconds)
            guard !Task.isCancelled else { return }
            self?.finishTimedSession(durationSeconds: seconds)
        }
    }

    private func pauseTimedSession() {
        guard let searchStart = timedSessionSearchStartNanoseconds else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if now >= searchStart {
            timedSessionElapsedNanoseconds += now - searchStart
        }
        timedSessionSearchStartNanoseconds = nil
        timedSessionTask?.cancel()
        timedSessionTask = nil
        stimulusPresentationState.pauseTimeBar()
        countdownAudioPlayer.pause()
        DiagnosticLog.event("session", "timed session paused; elapsedNanoseconds=\(timedSessionElapsedNanoseconds)")
    }

    private func finishTimedSession(durationSeconds: Int) {
        guard !hasTimedSessionEnded else { return }
        hasTimedSessionEnded = true
        postStopMaskTask?.cancel()
        postStopMaskTask = nil
        DiagnosticLog.event("session", "timed session finishing; durationSeconds=\(durationSeconds) score=\(completedTargetCount)")
        stimulusPresentationState.stopTimeBar()
        countdownAudioPlayer.pause()
        timedSessionTask = nil
        timedSessionSearchStartNanoseconds = nil
        speechRestartTask?.cancel()
        speechRestartTask = nil
        speechListener.stop()
        currentTrialMeasurement = nil
        keyboardInputListener.stop()
        trialPhase = .debriefing
        stimulusPresentationState.hide()

        do {
            try resultFileWriter.finishTimedExperiment(
                score: completedTargetCount,
                durationSeconds: durationSeconds,
                endTimeMS: elapsedMilliseconds()
            )
            statusMessage = "Time expired — final score: \(completedTargetCount)."
        } catch {
            statusMessage = "Time expired — final score: \(completedTargetCount), but the result couldn't be saved: \(error.localizedDescription)"
            print("SmartFOV123 result error: \(error.localizedDescription)")
        }
        synchronizeParticipantPresentation()
        if let timedSessionFinalSound, timedSessionFinalSound.volume > 0 {
            countdownAudioPlayer.playGong(sound: timedSessionFinalSound)
        }
        timedSessionFinalSound = nil
    }

    /// The Digital Crown returns the windowless experience to Home View,
    /// which backgrounds the privately deployed research app. Save and quiet
    /// the session synchronously before terminating the process.
    private func terminateWhenBackgrounded() -> Never {
        print("SmartFOV123 lifecycle: scene entered background; saving and stopping session work.")
        DiagnosticLog.event("lifecycle", "background cleanup begin; phase=\(String(describing: trialPhase)) trial=\(currentTrialIndex + 1)")
        let wasExperimentActive = hasExperimentBegun && !hasCompletedExperiment
        speechListener.prepareForBackground()
        keyboardInputListener.stop()
        countdownAudioPlayer.stop()
        timedSessionTask?.cancel()
        timedSessionTask = nil
        timedSessionSearchStartNanoseconds = nil
        speechRestartTask?.cancel()
        speechRestartTask = nil
        stimulusPresentationState.hide()
        do {
            try resultFileWriter.finishInterruptedExperiment(endTimeMS: elapsedMilliseconds())
        } catch {
            print("SmartFOV123 result error during background cleanup: \(error.localizedDescription)")
        }
        currentTrialMeasurement = nil
        immersiveSpaceState = .closed
        if wasExperimentActive {
            hasTimedSessionEnded = true
            trialPhase = .debriefing
            statusMessage = "Experiment interrupted when SmartFOV123 left the foreground."
            synchronizeParticipantPresentation()
        }
        DiagnosticLog.event("lifecycle", "background cleanup complete; wasExperimentActive=\(wasExperimentActive)")
        exit(EXIT_SUCCESS)
    }

}

private struct InProgressTrialMeasurement {
    let absoluteTrialStartMS: UInt64
    var digitRevealMS: UInt64?
    var timerStartMS: UInt64?
    var stopSignalStartMS: UInt64?
    var timerStopMS: UInt64?
    var speech: [CompletedTrialResults.SpeechDetection] = []
    var keyboard: [CompletedTrialResults.KeyboardDetection] = []
}
