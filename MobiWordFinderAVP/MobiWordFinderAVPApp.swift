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

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            StimulusCompositorLayer(appModel: appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
