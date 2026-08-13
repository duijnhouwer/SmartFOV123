import CompositorServices
import Metal
import SwiftUI

struct StimulusCompositorLayer: ImmersiveSpaceContent, CompositorLayerConfiguration {
    let appModel: AppModel

    var body: some ImmersiveSpaceContent {
        CompositorLayer(configuration: self) { @MainActor layerRenderer in
            if #available(visionOS 26.0, *) {
                layerRenderer.onSpatialEvent = { events in
                    for event in events where event.phase == .ended {
                        let identifier = event.trackingAreaIdentifier.rawValue
                        guard identifier != 0 else { continue }
                        appModel.handleSelection(identifier: identifier)
                    }
                }
            }
            Renderer.start(layerRenderer, appModel: appModel)
        }
    }

    func makeConfiguration(
        capabilities: LayerRenderer.Capabilities,
        configuration: inout LayerRenderer.Configuration
    ) {
        // Disabling foveation keeps the spatial sampling of the letter grid
        // uniform for this initial experimental implementation.
        configuration.isFoveationEnabled = false

        if capabilities.supportedDepthFormats.contains(.depth32Float) {
            configuration.depthFormat = .depth32Float
        }

        let layouts = capabilities.supportedLayouts(options: [])
        configuration.layout = layouts.contains(.dedicated) ? .dedicated : .layered

        if #available(visionOS 26.0, *),
           capabilities.supportedTrackingAreasFormats.contains(.r8Uint) {
            configuration.trackingAreasFormat = .r8Uint
            configuration.trackingAreasUsage = [.renderTarget, .shaderRead]
        }
    }
}
