import ARKit
import CompositorServices
import Metal
import QuartzCore

private extension LayerRenderer.Clock.Instant {
    var timeInterval: TimeInterval {
        let components = Self.epoch.duration(to: self).components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

private final class RenderTaskExecutor: TaskExecutor {
    static let shared = RenderTaskExecutor()
    private let queue = DispatchQueue(label: "EyeTestRenderThread", qos: .userInteractive)

    func enqueue(_ job: UnownedJob) {
        queue.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    nonisolated func asUnownedSerialExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
}

private struct SquareUniforms {
    var halfWidth: Float
    var halfHeight: Float
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float
}

private enum EyeTestRendererError: LocalizedError {
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

actor EyeTestRenderer {
    private static let maxFramesInFlight = 3

    private enum Phase: Int {
        case both = 0
        case leftOnly = 1
        case rightOnly = 2
    }

    private enum Eye {
        case left
        case right
    }

    private let layerRenderer: LayerRenderer
    private let appModel: EyeTestAppModel
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let cycleStart = CACurrentMediaTime()
    private var lastPublishedState: EyeTestAppModel.ImmersiveSpaceState?
    private var isWaitingForTracking = false
    #if !targetEnvironment(simulator)
    private let residencySets: [MTLResidencySet]
    private let endFrameEvent: MTLSharedEvent
    private var residencySetIndex = 0
    private var residencySetSignalValues = [UInt64](repeating: 0, count: maxFramesInFlight)
    private var nextSignalValue: UInt64 = 1
    #endif

    init(_ layerRenderer: LayerRenderer, appModel: EyeTestAppModel) throws {
        self.layerRenderer = layerRenderer
        self.appModel = appModel

        let device = layerRenderer.device
        guard let commandQueue = device.makeCommandQueue() else {
            throw EyeTestRendererError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue

        guard let library = device.makeDefaultLibrary() else {
            throw EyeTestRendererError.shaderLibraryMissing
        }
        guard let vertexFunction = library.makeFunction(name: "eyeTestVertex") else {
            throw EyeTestRendererError.shaderFunctionMissing("eyeTestVertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "eyeTestFragment") else {
            throw EyeTestRendererError.shaderFunctionMissing("eyeTestFragment")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Head-locked eye-test square"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = layerRenderer.configuration.colorFormat
        pipelineDescriptor.depthAttachmentPixelFormat = layerRenderer.configuration.depthFormat

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            throw EyeTestRendererError.pipelineCreationFailed(error)
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .greater
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw EyeTestRendererError.depthStateCreationFailed
        }
        self.depthState = depthState

        #if !targetEnvironment(simulator)
        do {
            self.residencySets = try (0..<Self.maxFramesInFlight).map { index in
                let descriptor = MTLResidencySetDescriptor()
                descriptor.label = "Eye-test frame \(index)"
                descriptor.initialCapacity = 4
                return try device.makeResidencySet(descriptor: descriptor)
            }
        } catch {
            throw EyeTestRendererError.residencySetCreationFailed(error)
        }

        guard let endFrameEvent = device.makeSharedEvent() else {
            throw EyeTestRendererError.residencySetCreationFailed(
                NSError(
                    domain: "HeadlockedEyeTest",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Metal couldn't create a frame synchronization event."]
                )
            )
        }
        self.endFrameEvent = endFrameEvent
        #endif
    }

    @MainActor
    static func start(_ layerRenderer: LayerRenderer, appModel: EyeTestAppModel) {
        Task(executorPreference: RenderTaskExecutor.shared) {
            do {
                let renderer = try EyeTestRenderer(layerRenderer, appModel: appModel)
                try await renderer.startARSession()
                await renderer.renderLoop()
            } catch {
                await MainActor.run {
                    appModel.statusMessage = error.localizedDescription
                    // The immersive scene may already be open even though renderer
                    // construction failed. Keep Stop available so the user can
                    // always dismiss that scene.
                    appModel.immersiveSpaceState = .open
                }
            }
        }
    }

    private func startARSession() async throws {
        do {
            try await arSession.run([worldTracking])
        } catch {
            throw EyeTestRendererError.arSessionFailed(error)
        }

        // ARKitSession.run can return while a provider is still transitioning
        // from initialized to running. Querying during that interval is a
        // client error on physical visionOS.
        for _ in 0..<200 {
            if worldTracking.state == .running {
                return
            }
            if worldTracking.state == .stopped {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw EyeTestRendererError.worldTrackingDidNotStart(worldTracking.state.description)
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

    private func publishState(_ state: EyeTestAppModel.ImmersiveSpaceState) {
        guard lastPublishedState != state else { return }
        lastPublishedState = state
        Task { @MainActor in
            appModel.immersiveSpaceState = state
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

        // Validate tracking before acquiring drawables. Once drawables are
        // acquired and submission starts, each one must be presented.
        guard worldTracking.state == .running,
              let deviceAnchor = worldTracking.queryDeviceAnchor(
                atTimestamp: timing.presentationTime.timeInterval
              ) else {
            publishTrackingWaitIfNeeded()
            return
        }
        clearTrackingWaitIfNeeded()

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

        commandBuffer.label = "Eye-test frame"

        #if !targetEnvironment(simulator)
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
            render(drawable, into: commandBuffer)
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

    private func render(_ drawable: LayerRenderer.Drawable, into commandBuffer: MTLCommandBuffer) {
        let phaseIndex = Int(CACurrentMediaTime() - cycleStart) % 3
        let phase = Phase(rawValue: phaseIndex) ?? .both

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

            let eye = eye(for: view, index: viewIndex, viewCount: drawable.views.count)
            encoder.label = eye == .left ? "Left eye" : "Right eye"
            encoder.setViewport(textureMap.viewport)

            if let color = color(for: eye, phase: phase) {
                let viewport = textureMap.viewport
                let aspect = Float(viewport.width / viewport.height)
                var uniforms = makeUniforms(color: color, aspect: aspect)

                encoder.setRenderPipelineState(pipelineState)
                encoder.setDepthStencilState(depthState)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<SquareUniforms>.stride, index: 0)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SquareUniforms>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }

            encoder.endEncoding()
        }

    }

    private func publishTrackingWaitIfNeeded() {
        guard !isWaitingForTracking else { return }
        isWaitingForTracking = true
        publishError("Waiting for headset tracking before presenting the test.")
    }

    private func clearTrackingWaitIfNeeded() {
        guard isWaitingForTracking else { return }
        isWaitingForTracking = false
        Task { @MainActor in
            appModel.statusMessage = nil
        }
    }

    private func eye(
        for view: LayerRenderer.Drawable.View,
        index: Int,
        viewCount: Int
    ) -> Eye {
        guard viewCount > 1 else { return .left }

        let horizontalOffset = view.transform.columns.3.x
        if abs(horizontalOffset) > 0.0001 {
            return horizontalOffset < 0 ? .left : .right
        }
        return index == 0 ? .left : .right
    }

    private func color(for eye: Eye, phase: Phase) -> SIMD4<Float>? {
        switch phase {
        case .both:
            return eye == .left ? SIMD4(1, 0, 0, 1) : SIMD4(0, 1, 0, 1)
        case .leftOnly:
            return eye == .left ? SIMD4(1, 0, 0, 1) : nil
        case .rightOnly:
            return eye == .right ? SIMD4(0, 1, 0, 1) : nil
        }
    }

    private func makeUniforms(color: SIMD4<Float>, aspect: Float) -> SquareUniforms {
        let halfHeight: Float = 0.12
        return SquareUniforms(
            halfWidth: halfHeight / max(aspect, 0.01),
            halfHeight: halfHeight,
            red: color.x,
            green: color.y,
            blue: color.z,
            alpha: color.w
        )
    }
}
