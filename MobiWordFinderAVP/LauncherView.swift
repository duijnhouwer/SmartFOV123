import SwiftUI

struct LauncherView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var safetyStopTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 18) {
            Text("MobiWordFinderAVP")
                .font(.title)

            Text(appModel.trialDescription)
                .multilineTextAlignment(.center)

            Text("The grid is presented binocularly using the geometry in experiment.json. Keep this window open while testing; the trial stops automatically after 30 seconds.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { @MainActor in
                    await toggleTest()
                }
            } label: {
                Text(buttonTitle)
            }
            .disabled(appModel.immersiveSpaceState == .inTransition || appModel.experiment == nil)

            if let statusMessage = appModel.statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .onDisappear {
            safetyStopTask?.cancel()
            Task { @MainActor in
                guard appModel.immersiveSpaceState == .open else { return }
                await stopTest(message: nil)
            }
        }
    }

    private var buttonTitle: String {
        switch appModel.immersiveSpaceState {
        case .closed:
            return "Start trial"
        case .inTransition:
            return "Please wait…"
        case .open:
            return "Stop trial"
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
        safetyStopTask?.cancel()
        appModel.immersiveSpaceState = .inTransition
        appModel.statusMessage = nil

        let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)

        switch result {
        case .opened:
            appModel.immersiveSpaceState = .open
            scheduleSafetyStop()
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
        safetyStopTask?.cancel()
        safetyStopTask = nil
        appModel.immersiveSpaceState = .inTransition
        await dismissImmersiveSpace()
        appModel.immersiveSpaceState = .closed
        appModel.statusMessage = message
    }

    @MainActor
    private func scheduleSafetyStop() {
        safetyStopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled,
                  appModel.immersiveSpaceState == .open else { return }
            await stopTest(message: "The test stopped automatically after 30 seconds.")
        }
    }
}
