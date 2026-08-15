import CompositorServices
import Metal
import SwiftUI

struct StimulusCompositorLayer: ImmersiveSpaceContent, CompositorLayerConfiguration {
    let appModel: AppModel

    var body: some ImmersiveSpaceContent {
        CompositorLayer(configuration: self) { @MainActor layerRenderer in
            appModel.startWindowlessExperienceIfNeeded()
            Renderer.start(layerRenderer, appModel: appModel)
        }
    }

    func makeConfiguration(
        capabilities: LayerRenderer.Capabilities,
        configuration: inout LayerRenderer.Configuration
    ) {
        // Disabling foveation keeps the spatial sampling of the digit grid
        // uniform for this initial experimental implementation.
        configuration.isFoveationEnabled = false

        if capabilities.supportedDepthFormats.contains(.depth32Float) {
            configuration.depthFormat = .depth32Float
        }

        let layouts = capabilities.supportedLayouts(options: [])
        configuration.layout = layouts.contains(.dedicated) ? .dedicated : .layered
    }
}
