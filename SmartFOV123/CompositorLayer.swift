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
        // Request foveation by default. A protocol can explicitly disable it
        // with foveated_rendering: false.
        let foveationEnabled = appModel.foveatedRendering
            && capabilities.supportsFoveation
        configuration.isFoveationEnabled = foveationEnabled

        if capabilities.supportedDepthFormats.contains(.depth32Float) {
            configuration.depthFormat = .depth32Float
        }

        let options: LayerRenderer.Capabilities.SupportedLayoutsOptions = foveationEnabled
            ? [.foveationEnabled]
            : []
        let layouts = capabilities.supportedLayouts(options: options)
        configuration.layout = layouts.contains(.dedicated) ? .dedicated : .layered
    }
}
