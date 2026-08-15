import SwiftUI

@main
struct SmartFOV123App: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            StimulusCompositorLayer(appModel: appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
