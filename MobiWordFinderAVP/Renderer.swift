import ARKit
import CompositorServices
import Foundation
import Metal
import QuartzCore
import simd

private extension LayerRenderer.Clock.Instant {
    var timeInterval: TimeInterval {
        let components = Self.epoch.duration(to: self).components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private final class RenderTaskExecutor: TaskExecutor {
    static let shared = RenderTaskExecutor()
    private let queue = DispatchQueue(label: "MobiWordFinderAVPRenderThread", qos: .userInteractive)

    func enqueue(_ job: UnownedJob) {
        queue.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    nonisolated func asUnownedSerialExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
}

private struct StimulusUniforms {
    var clipFromDevice: simd_float4x4
    var centerMeters: SIMD2<Float>
    var halfSizeMeters: SIMD2<Float>
    var fovCenterMeters: SIMD2<Float>
    var fovHalfSizeMeters: SIMD2<Float>
    var distanceMeters: Float
}

private struct StimulusGeometry {
    let distanceMeters: Float
    let fovCenterMeters: SIMD2<Float>
    let fovHalfSizeMeters: SIMD2<Float>
    let gridCenterMeters: SIMD2<Float>
    let digitHeightMeters: Float

    init(configuration: StimulusConfiguration) {
        distanceMeters = configuration.distanceMeters
        fovCenterMeters = SIMD2(
            Self.offsetMeters(
                degrees: configuration.fovHorizontalOffsetDegrees,
                distance: configuration.distanceMeters
            ),
            Self.offsetMeters(
                degrees: configuration.fovVerticalOffsetDegrees,
                distance: configuration.distanceMeters
            )
        )
        fovHalfSizeMeters = SIMD2(
            Self.sizeMeters(
                degrees: configuration.fovWidthDegrees,
                distance: configuration.distanceMeters
            ) / 2,
            Self.sizeMeters(
                degrees: configuration.fovHeightDegrees,
                distance: configuration.distanceMeters
            ) / 2
        )
        gridCenterMeters = fovCenterMeters
        digitHeightMeters = Self.sizeMeters(
            degrees: configuration.digitHeightArcmin / 60,
            distance: configuration.distanceMeters
        )
    }

    private static func sizeMeters(degrees: Float, distance: Float) -> Float {
        2 * distance * tan(degrees * .pi / 360)
    }

    private static func offsetMeters(degrees: Float, distance: Float) -> Float {
        distance * tan(degrees * .pi / 180)
    }
}

private enum RendererError: LocalizedError {
    case experimentMissing
    case commandQueueCreationFailed
    case shaderLibraryMissing
    case shaderFunctionMissing(String)
    case pipelineCreationFailed(Error)
    case depthStateCreationFailed
    case residencySetCreationFailed(Error)
    case arSessionFailed(Error)
    case worldTrackingDidNotStart(String)

    var errorDescription: String? {
        switch self {
        case .experimentMissing:
            return "No valid experiment is available to render."
        case .commandQueueCreationFailed:
            return "Metal couldn't create a command queue."
        case .shaderLibraryMissing:
            return "The app's Metal shader library is missing."
        case .shaderFunctionMissing(let name):
            return "The Metal shader function \(name) is missing."
        case .pipelineCreationFailed(let error):
            return "Metal couldn't create the render pipeline: \(error.localizedDescription)"
        case .depthStateCreationFailed:
            return "Metal couldn't create the depth state."
        case .residencySetCreationFailed(let error):
            return "Metal couldn't make drawable textures resident: \(error.localizedDescription)"
        case .arSessionFailed(let error):
            return "ARKit couldn't start device tracking: \(error.localizedDescription)"
        case .worldTrackingDidNotStart(let state):
            return "ARKit device tracking did not start (provider state: \(state))."
        }
    }
}

actor Renderer {
    private static let maxFramesInFlight = 3

    private let layerRenderer: LayerRenderer
    private let appModel: AppModel
    private let experiment: Experiment
    private let presentationGeneration: Int
    private let geometry: StimulusGeometry
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private let commandQueue: MTLCommandQueue
    private let visualPipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let maskedStimulusTexture: StimulusTexture
    private let revealedStimulusTexture: StimulusTexture
    private let presentationState: StimulusPresentationState
    private var loggedProjectionEyes = Set<String>()
    private var lastPublishedState: AppModel.ImmersiveSpaceState?
    private var isWaitingForDeviceTracking = false
    #if !targetEnvironment(simulator)
    private let residencySets: [MTLResidencySet]
    private let endFrameEvent: MTLSharedEvent
    private var residencySetIndex = 0
    private var residencySetSignalValues = [UInt64](repeating: 0, count: maxFramesInFlight)
    private var nextSignalValue: UInt64 = 1
    #endif

    init(
        _ layerRenderer: LayerRenderer,
        appModel: AppModel,
        experiment: Experiment,
        trialsRemaining: Int,
        presentationGeneration: Int
    ) throws {
        self.layerRenderer = layerRenderer
        self.appModel = appModel
        self.experiment = experiment
        self.presentationGeneration = presentationGeneration
        self.presentationState = appModel.stimulusPresentationState
        self.geometry = StimulusGeometry(configuration: experiment.configuration.stimulus)

        let device = layerRenderer.device
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue
        self.maskedStimulusTexture = try StimulusTexture(
            device: device,
            commandQueue: commandQueue,
            experiment: experiment,
            trialsRemaining: trialsRemaining,
            presentation: .masked
        )
        self.revealedStimulusTexture = try StimulusTexture(
            device: device,
            commandQueue: commandQueue,
            experiment: experiment,
            trialsRemaining: trialsRemaining,
            presentation: .revealed
        )

        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.shaderLibraryMissing
        }
        guard let vertexFunction = library.makeFunction(name: "stimulusVertex") else {
            throw RendererError.shaderFunctionMissing("stimulusVertex")
        }
        guard let visualFragmentFunction = library.makeFunction(name: "stimulusFragment") else {
            throw RendererError.shaderFunctionMissing("stimulusFragment")
        }

        func makePipelineDescriptor(fragmentFunction: MTLFunction) -> MTLRenderPipelineDescriptor {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "NumberFinder visual pipeline"
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = layerRenderer.configuration.colorFormat
            // The fragment shader emits the completed stimulus pixel using
            // visionOS's required premultiplied-alpha convention. Replacing
            // prior pixels lets black in the optical-see-through simulation
            // punch transparent holes through previously drawn surfaces.
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.depthAttachmentPixelFormat = layerRenderer.configuration.depthFormat
            return descriptor
        }

        do {
            visualPipelineState = try device.makeRenderPipelineState(
                descriptor: makePipelineDescriptor(fragmentFunction: visualFragmentFunction)
            )
        } catch let error as RendererError {
            throw error
        } catch {
            throw RendererError.pipelineCreationFailed(error)
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        // Every WordFinder primitive lies on one stimulus plane. Comparing
        // coplanar depths causes unstable z-fighting between the FOV, boxes,
        // and glyphs. Always accept fragments so painter's order determines
        // their appearance while retaining depth writes for composition.
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw RendererError.depthStateCreationFailed
        }
        self.depthState = depthState

        #if !targetEnvironment(simulator)
        do {
            self.residencySets = try (0..<Self.maxFramesInFlight).map { index in
                let descriptor = MTLResidencySetDescriptor()
                descriptor.label = "WordFinder frame \(index)"
                descriptor.initialCapacity = 8
                return try device.makeResidencySet(descriptor: descriptor)
            }
        } catch {
            throw RendererError.residencySetCreationFailed(error)
        }

        guard let endFrameEvent = device.makeSharedEvent() else {
            throw RendererError.residencySetCreationFailed(
                NSError(
                    domain: "MobiWordFinderAVP",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Metal couldn't create a frame synchronization event."]
                )
            )
        }
        self.endFrameEvent = endFrameEvent
        #endif
    }

    @MainActor
    static func start(_ layerRenderer: LayerRenderer, appModel: AppModel) {
        guard let experiment = appModel.experiment else {
            appModel.statusMessage = RendererError.experimentMissing.localizedDescription
            return
        }
        let trialsRemaining = max(0, appModel.trialCount - appModel.currentTrialIndex)
        let presentationGeneration = appModel.immersivePresentationGeneration
        Task(executorPreference: RenderTaskExecutor.shared) {
            do {
                let renderer = try Renderer(
                    layerRenderer,
                    appModel: appModel,
                    experiment: experiment,
                    trialsRemaining: trialsRemaining,
                    presentationGeneration: presentationGeneration
                )
                try await renderer.startARSession()
                await renderer.renderLoop()
            } catch {
                await MainActor.run {
                    appModel.statusMessage = error.localizedDescription
                    appModel.publishImmersiveSpaceState(
                        .open,
                        generation: presentationGeneration
                    )
                }
            }
        }
    }

    private func startARSession() async throws {
        do {
            try await arSession.run([worldTracking])
        } catch {
            throw RendererError.arSessionFailed(error)
        }

        for _ in 0..<200 {
            if worldTracking.state == .running {
                return
            }
            if worldTracking.state == .stopped {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw RendererError.worldTrackingDidNotStart(worldTracking.state.description)
    }

    private func renderLoop() {
        while true {
            switch layerRenderer.state {
            case .running:
                publishState(.open)
                autoreleasepool {
                    renderFrame()
                }
            case .paused:
                layerRenderer.waitUntilRunning()
            case .invalidated:
                publishState(.closed)
                return
            @unknown default:
                publishState(.closed)
                return
            }
        }
    }

    private func publishState(_ state: AppModel.ImmersiveSpaceState) {
        guard lastPublishedState != state else { return }
        lastPublishedState = state
        Task { @MainActor in
            appModel.publishImmersiveSpaceState(
                state,
                generation: presentationGeneration
            )
        }
    }

    private func publishError(_ message: String) {
        Task { @MainActor in
            appModel.statusMessage = message
        }
    }

    private func renderFrame() {
        guard let frame = layerRenderer.queryNextFrame() else {
            Thread.sleep(forTimeInterval: 0.001)
            return
        }

        #if !targetEnvironment(simulator)
        residencySetIndex = (residencySetIndex + 1) % Self.maxFramesInFlight
        let reusableFrameSignalValue = residencySetSignalValues[residencySetIndex]
        guard endFrameEvent.wait(untilSignaledValue: reusableFrameSignalValue, timeoutMS: 10_000) else {
            publishError("Timed out waiting for a previous Metal frame to finish.")
            return
        }
        let residencySet = residencySets[residencySetIndex]
        residencySet.removeAllAllocations()
        residencySet.commit()
        #endif

        frame.startUpdate()
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)

        guard worldTracking.state == .running,
              let deviceAnchor = worldTracking.queryDeviceAnchor(
                atTimestamp: timing.presentationTime.timeInterval
              ) else {
            publishDeviceTrackingWaitIfNeeded()
            return
        }
        clearDeviceTrackingWaitIfNeeded()

        let drawables: [LayerRenderer.Drawable]
        if #available(visionOS 26.0, *) {
            drawables = frame.queryDrawables()
        } else if let drawable = frame.queryDrawable() {
            drawables = [drawable]
        } else {
            drawables = []
        }
        guard !drawables.isEmpty else { return }

        for drawable in drawables {
            drawable.deviceAnchor = deviceAnchor
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "WordFinder frame"
        let stimulusTexture: MTLTexture
        let presentationContent = presentationState.content
        let rendersStimulus: Bool
        switch presentationContent {
        case .hidden:
            stimulusTexture = maskedStimulusTexture.texture
            rendersStimulus = false
        case .maskedGrid:
            stimulusTexture = maskedStimulusTexture.texture
            rendersStimulus = true
        case .revealedGrid:
            stimulusTexture = revealedStimulusTexture.texture
            rendersStimulus = true
        }

        #if !targetEnvironment(simulator)
        residencySet.addAllocation(stimulusTexture)
        for drawable in drawables {
            for texture in drawable.colorTextures {
                residencySet.addAllocation(texture)
            }
            for texture in drawable.depthTextures {
                residencySet.addAllocation(texture)
            }
        }
        residencySet.commit()
        commandBuffer.useResidencySet(residencySet)
        #endif

        commandBuffer.addCompletedHandler { [weak appModel] completedBuffer in
            guard completedBuffer.status == .error else { return }
            let message = completedBuffer.error?.localizedDescription ?? "Unknown Metal command-buffer error."
            Task { @MainActor in
                appModel?.statusMessage = "Metal failed to render a frame: \(message)"
            }
        }

        frame.startSubmission()
        for drawable in drawables {
            render(
                drawable,
                into: commandBuffer,
                stimulusTexture: stimulusTexture,
                rendersStimulus: rendersStimulus
            )
            drawable.encodePresent(commandBuffer: commandBuffer)
        }
        #if !targetEnvironment(simulator)
        let signalValue = nextSignalValue
        nextSignalValue += 1
        residencySetSignalValues[residencySetIndex] = signalValue
        commandBuffer.encodeSignalEvent(endFrameEvent, value: signalValue)
        #endif
        commandBuffer.commit()
        frame.endSubmission()
    }

    private func render(
        _ drawable: LayerRenderer.Drawable,
        into commandBuffer: MTLCommandBuffer,
        stimulusTexture: MTLTexture,
        rendersStimulus: Bool
    ) {
        for (viewIndex, view) in drawable.views.enumerated() {
            let textureMap = view.textureMap
            guard textureMap.textureIndex < drawable.colorTextures.count,
                  textureMap.textureIndex < drawable.depthTextures.count else {
                publishError("Compositor Services returned an invalid texture map.")
                continue
            }

            let descriptor = MTLRenderPassDescriptor()
            let colorAttachment = descriptor.colorAttachments[0]!
            colorAttachment.texture = drawable.colorTextures[textureMap.textureIndex]
            colorAttachment.slice = textureMap.sliceIndex
            colorAttachment.loadAction = .clear
            colorAttachment.storeAction = .store
            colorAttachment.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

            let depthAttachment = descriptor.depthAttachment!
            depthAttachment.texture = drawable.depthTextures[textureMap.textureIndex]
            depthAttachment.slice = textureMap.sliceIndex
            depthAttachment.loadAction = .clear
            depthAttachment.storeAction = .store
            depthAttachment.clearDepth = 0

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                publishError("Metal couldn't create a render encoder.")
                continue
            }

            encoder.label = viewIndex == 0 ? "WordFinder left view" : "WordFinder right view"
            encoder.setViewport(textureMap.viewport)
            encoder.setRenderPipelineState(visualPipelineState)
            encoder.setDepthStencilState(depthState)
            encoder.setFragmentTexture(stimulusTexture, index: 0)

            let clipFromDevice = drawable.computeProjection(viewIndex: viewIndex) * view.transform.inverse
            logProjectionMetricsIfNeeded(
                viewIndex: viewIndex,
                viewTransform: view.transform,
                clipFromDevice: clipFromDevice,
                viewport: textureMap.viewport
            )
            if rendersStimulus,
               shouldRenderStimulus(viewIndex: viewIndex, viewTransform: view.transform) {
                drawStimulus(encoder: encoder, clipFromDevice: clipFromDevice)
            }
            encoder.endEncoding()
        }
    }

    private func shouldRenderStimulus(
        viewIndex: Int,
        viewTransform: simd_float4x4
    ) -> Bool {
        let configuredEye = experiment.configuration.stimulus.eye
        guard configuredEye != .both else { return true }
        return configuredEye == renderedEye(viewIndex: viewIndex, viewTransform: viewTransform)
    }

    private func renderedEye(
        viewIndex: Int,
        viewTransform: simd_float4x4
    ) -> StimulusEye {
        let eyeOffset = viewTransform.columns.3.x
        if eyeOffset < -0.0001 {
            return .left
        }
        if eyeOffset > 0.0001 {
            return .right
        }

        // The physical headset supplies signed per-eye translations. Retain a
        // deterministic fallback for simulator/runtime layouts without one.
        return viewIndex == 0 ? .left : .right
    }

    private func logProjectionMetricsIfNeeded(
        viewIndex: Int,
        viewTransform: simd_float4x4,
        clipFromDevice: simd_float4x4,
        viewport: MTLViewport
    ) {
        let eyeLabel = renderedEye(
            viewIndex: viewIndex,
            viewTransform: viewTransform
        ).rawValue
        guard loggedProjectionEyes.insert(eyeLabel).inserted else { return }

        let halfHeight = geometry.digitHeightMeters / 2
        let bottom = clipFromDevice * SIMD4<Float>(
            geometry.gridCenterMeters.x,
            geometry.gridCenterMeters.y - halfHeight,
            -geometry.distanceMeters,
            1
        )
        let top = clipFromDevice * SIMD4<Float>(
            geometry.gridCenterMeters.x,
            geometry.gridCenterMeters.y + halfHeight,
            -geometry.distanceMeters,
            1
        )
        guard bottom.w != 0, top.w != 0 else { return }
        let normalizedDeviceHeight = abs(top.y / top.w - bottom.y / bottom.w)
        let projectedPixelHeight = Double(normalizedDeviceHeight) * viewport.height / 2
        let configuredArcminutes = experiment.configuration.stimulus.digitHeightArcmin
        print(
            String(
                format: "MobiWordFinder: %@ eye viewport %.0f x %.0f; %.1f arcmin digit cap height projects to %.2f pixels.",
                eyeLabel,
                viewport.width,
                viewport.height,
                configuredArcminutes,
                projectedPixelHeight
            )
        )
    }

    private func drawStimulus(
        encoder: MTLRenderCommandEncoder,
        clipFromDevice: simd_float4x4
    ) {
        drawTexturedQuad(
            encoder: encoder,
            clipFromDevice: clipFromDevice,
            center: geometry.fovCenterMeters,
            halfSize: geometry.fovHalfSizeMeters
        )
    }

    private func drawTexturedQuad(
        encoder: MTLRenderCommandEncoder,
        clipFromDevice: simd_float4x4,
        center: SIMD2<Float>,
        halfSize: SIMD2<Float>
    ) {
        var uniforms = StimulusUniforms(
            clipFromDevice: clipFromDevice,
            centerMeters: center,
            halfSizeMeters: halfSize,
            fovCenterMeters: geometry.fovCenterMeters,
            fovHalfSizeMeters: geometry.fovHalfSizeMeters,
            distanceMeters: geometry.distanceMeters
        )
        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<StimulusUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    private func publishDeviceTrackingWaitIfNeeded() {
        guard !isWaitingForDeviceTracking else { return }
        isWaitingForDeviceTracking = true
        publishError("Waiting for headset tracking before presenting the trial.")
    }

    private func clearDeviceTrackingWaitIfNeeded() {
        guard isWaitingForDeviceTracking else { return }
        isWaitingForDeviceTracking = false
        Task { @MainActor in
            if appModel.statusMessage == "Waiting for headset tracking before presenting the trial." {
                appModel.statusMessage = nil
            }
        }
    }
}
