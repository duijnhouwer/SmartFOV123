import SwiftUI

@main
struct HeadlockedEyeTestApp: App {
    private let launcherWindowID = "LauncherWindow"
    @State private var appModel = EyeTestAppModel()

    var body: some Scene {
        WindowGroup(id: launcherWindowID) {
            LauncherView()
                .environment(appModel)
        }

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            EyeTestCompositorLayer(appModel: appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
