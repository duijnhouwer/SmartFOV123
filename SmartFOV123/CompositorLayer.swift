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
        // Let visionOS concentrate rasterization density at the participant's
        // fixation point, where high-acuity digit reading occurs.
        let foveationEnabled = capabilities.supportsFoveation
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
