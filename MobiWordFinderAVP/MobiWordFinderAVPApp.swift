import SwiftUI

@main
struct MobiWordFinderAVPApp: App {
    private let launcherWindowID = "LauncherWindow"
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup(id: launcherWindowID) {
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
