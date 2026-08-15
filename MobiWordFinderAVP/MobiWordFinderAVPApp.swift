import SwiftUI

@main
struct MobiWordFinderAVPApp: App {
    private let appHostWindowID = "AppHostWindow"
    private let operatorWindowID = "OperatorWindow"
    @State private var appModel = AppModel()

    var body: some Scene {
        // Keep this host window underneath the pushed operator window. On
        // visionOS the last ordinary window is only backgrounded when its X
        // is pinched, so its onDisappear isn't called. A pushed window has
        // this host scene underneath it and is actually removed when closed,
        // giving LauncherView a reliable synchronous cleanup callback.
        WindowGroup(id: appHostWindowID) {
            AppHostView(operatorWindowID: operatorWindowID)
                .environment(appModel)
        }
        .defaultSize(width: 512, height: 720)

        WindowGroup(id: operatorWindowID) {
            LauncherView()
                .environment(appModel)
        }
        .defaultSize(width: 512, height: 720)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            StimulusCompositorLayer(appModel: appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        ImmersiveSpace(id: appModel.participantSpaceID) {
            ParticipantPromptView(appModel: appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

private struct AppHostView: View {
    let operatorWindowID: String

    @Environment(\.pushWindow) private var pushWindow
    @State private var hasPushedOperatorWindow = false

    var body: some View {
        ProgressView("Starting MobiWordFinderAVP…")
            .task {
                guard !hasPushedOperatorWindow else { return }
                hasPushedOperatorWindow = true
                pushWindow(id: operatorWindowID)
            }
    }
}
