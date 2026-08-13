import CompositorServices
import Metal
import SwiftUI

struct EyeTestCompositorLayer: ImmersiveSpaceContent, CompositorLayerConfiguration {
    let appModel: EyeTestAppModel

    var body: some ImmersiveSpaceContent {
        CompositorLayer(configuration: self) { @MainActor layerRenderer in
            EyeTestRenderer.start(layerRenderer, appModel: appModel)
        }
    }

    func makeConfiguration(
        capabilities: LayerRenderer.Capabilities,
        configuration: inout LayerRenderer.Configuration
    ) {
        // This is a diagnostic with two simple per-eye render passes. Disabling
        // foveation removes variable-rate texture mapping from the test.
        configuration.isFoveationEnabled = false

        if capabilities.supportedDepthFormats.contains(.depth32Float) {
            configuration.depthFormat = .depth32Float
        }

        let layouts = capabilities.supportedLayouts(options: [])
        configuration.layout = layouts.contains(.dedicated) ? .dedicated : .layered
    }
}
