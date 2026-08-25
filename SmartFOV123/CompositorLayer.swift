import CompositorServices
import Metal
import SwiftUI

struct StimulusCompositorLayer: CompositorContent, CompositorLayerConfiguration {
    @Bindable var appModel: AppModel

    var body: some CompositorContent {
        CompositorLayer(configuration: self) { @MainActor layerRenderer in
            appModel.startWindowlessExperienceIfNeeded()
            Renderer.start(layerRenderer, appModel: appModel)
        }
        // Apple's intensity is the amount of passthrough retained: 1 is
        // unchanged and 0 is black. The protocol deliberately uses the more
        // intuitive inverse convention, where 1 means fully dimmed.
        .preferredSurroundingsEffect(.dim(intensity: 1 - appModel.passthroughDimming))
    }

    func makeConfiguration(
        capabilities: LayerRenderer.Capabilities,
        configuration: inout LayerRenderer.Configuration
    ) {
        // Foveation is an app-session setting loaded from Documents/config.json
        // before the compositor layer is configured.
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
