import SwiftUI

struct LauncherView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var hasAttemptedAutomaticStart = false

    var body: some View {
        VStack(spacing: 18) {
            Text("MobiWordFinderAVP")
                .font(.title)

            Text(appModel.trialDescription)
                .multilineTextAlignment(.center)

            Text("The sequence starts automatically. Follow the target and spoken prompts in the immersive view; correct responses advance to the next trial.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if appModel.isListening {
                Label(listeningLabel, systemImage: "mic.fill")
                    .foregroundStyle(.green)
            }

            if let recognizedSpeech = appModel.recognizedSpeech {
                Text("Heard: \(recognizedSpeech)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage = appModel.statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(appModel.hasConfigurationError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .task {
            guard !hasAttemptedAutomaticStart else { return }
            hasAttemptedAutomaticStart = true
            guard appModel.immersiveSpaceState == .closed,
                  appModel.plan != nil,
                  !appModel.hasCompletedExperiment else { return }
            await startTest()
        }
        .onDisappear {
            // Apple doesn't normally recommend terminating an application in
            // response to a window closing. This is a privately deployed
            // research app, however, and closing its sole visible operator
            // window explicitly means "end the session." Terminating here is
            // synchronous, so no immersive stimulus or onboarding prompt can
            // become stranded by cancellation of an asynchronous Task.
            appModel.terminateResearchApplication()
        }
        .onChange(of: appModel.completedTrialToken) { _, _ in
            Task { @MainActor in
                guard appModel.immersiveSpaceState == .open else { return }
                await stopTest(message: nil)
                appModel.advanceAfterCompletedTrial()
                if !appModel.hasCompletedExperiment {
                    await startTest()
                }
            }
        }
        .onChange(of: appModel.beginExperimentToken) { _, _ in
            Task { @MainActor in
                guard appModel.immersiveSpaceState == .open else { return }
                await stopTest(message: nil)
                await startTest()
            }
        }
    }

    private var listeningLabel: String {
        switch appModel.trialPhase {
        case .participantConfirmation:
            return "Listening for yes, no, or quit"
        case .instructions:
            return "Listening for begin or quit"
        case .participantNumber, .targetCue, .search:
            return "Listening for digits"
        }
    }

    @MainActor
    private func startTest() async {
        appModel.immersiveSpaceState = .inTransition
        appModel.statusMessage = "Generating a valid trial grid…"
        guard await appModel.prepareCurrentTrial() else {
            appModel.immersiveSpaceState = .closed
            appModel.statusMessage = "No scheduled trial is available."
            return
        }
        appModel.statusMessage = "Requesting microphone and speech-recognition access…"

        guard await appModel.requestSpeechAuthorization() else {
            appModel.immersiveSpaceState = .closed
            return
        }

        appModel.prepareImmersivePresentation()
        appModel.beginImmersivePresentation()

        let result = await openImmersiveSpace(id: appModel.activeImmersiveSpaceID)

        switch result {
        case .opened:
            appModel.immersiveSpaceState = .open
            appModel.markCurrentTrialStartedIfReady()
            await appModel.startSpeechConfirmation()
        case .userCancelled:
            appModel.immersiveSpaceState = .closed
            appModel.statusMessage = "The immersive-space request was cancelled."
        case .error:
            appModel.immersiveSpaceState = .closed
            appModel.statusMessage = "visionOS couldn't open the immersive space. Check the Xcode console for details."
        @unknown default:
            appModel.immersiveSpaceState = .closed
            appModel.statusMessage = "visionOS returned an unknown immersive-space result."
        }
    }

    @MainActor
    private func stopTest(message: String?) async {
        await appModel.stopSpeechConfirmation()
        appModel.immersiveSpaceState = .inTransition
        await dismissImmersiveSpace()
        appModel.immersiveSpaceState = .closed
        appModel.statusMessage = message
    }

}
