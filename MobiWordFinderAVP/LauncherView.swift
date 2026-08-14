import SwiftUI

struct LauncherView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack(spacing: 18) {
            Text("MobiWordFinderAVP")
                .font(.title)

            Text(appModel.trialDescription)
                .multilineTextAlignment(.center)

            Text("Start the sequence here, then follow the target and spoken prompts in the immersive view. Correct responses advance automatically; return to this window only if you need to stop.")
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

            Button {
                Task { @MainActor in
                    await toggleTest()
                }
            } label: {
                Text(buttonTitle)
            }
            .disabled(
                appModel.immersiveSpaceState == .inTransition
                    || appModel.plan == nil
                    || appModel.hasCompletedExperiment
            )

            if let statusMessage = appModel.statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(appModel.hasConfigurationError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .onDisappear {
            Task { @MainActor in
                guard appModel.immersiveSpaceState == .open else { return }
                await stopTest(message: nil)
            }
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

    private var buttonTitle: String {
        switch appModel.immersiveSpaceState {
        case .closed:
            return "Start sequence"
        case .inTransition:
            return "Please wait…"
        case .open:
            return "Stop sequence"
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
    private func toggleTest() async {
        switch appModel.immersiveSpaceState {
        case .closed:
            await startTest()
        case .open:
            await stopTest(message: nil)
        case .inTransition:
            break
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
        appModel.stopSpeechConfirmation()
        appModel.immersiveSpaceState = .inTransition
        await dismissImmersiveSpace()
        appModel.immersiveSpaceState = .closed
        appModel.statusMessage = message
    }

}
