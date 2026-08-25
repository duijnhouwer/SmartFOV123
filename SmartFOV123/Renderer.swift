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
    private let queue = DispatchQueue(label: "SmartFOV123RenderThread", qos: .userInteractive)

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
    var distanceMeters: Float
    var uvMaxX: Float
}

private struct StimulusGeometry {
    let distanceMeters: Float
    let fovCenterMeters: SIMD2<Float>
    let fovHalfSizeMeters: SIMD2<Float>
    let digitHeightMeters: Float
    let timeBarLeftMeters: Float
    let timeBarCenterYMeters: Float
    let timeBarWidthMeters: Float
    let timeBarHalfHeightMeters: Float

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
                degrees: configuration.fovZoomedWidthDegrees,
                distance: configuration.distanceMeters
            ) / 2,
            Self.sizeMeters(
                degrees: configuration.fovZoomedHeightDegrees,
                distance: configuration.distanceMeters
            ) / 2
        )
        digitHeightMeters = Self.sizeMeters(
            degrees: configuration.digitHeightArcmin / 60,
            distance: configuration.distanceMeters
        ) * configuration.fovHeightScaleFactor
        let tileWidthMeters = Self.sizeMeters(
            degrees: configuration.tileWidthArcmin / 60,
            distance: configuration.distanceMeters
        )
        let tileHeightMeters = Self.sizeMeters(
            degrees: configuration.tileHeightArcmin / 60,
            distance: configuration.distanceMeters
        )
        let gutterMeters = Self.sizeMeters(
            degrees: configuration.tileGutterArcmin / 60,
            distance: configuration.distanceMeters
        )
        let innerMarginMeters = Self.sizeMeters(
            degrees: configuration.surroundInnerMarginArcmin / 60,
            distance: configuration.distanceMeters
        )
        let backHeightMeters = Self.sizeMeters(
            degrees: configuration.timeBarBackHeightArcmin / 60,
            distance: configuration.distanceMeters
        )
        timeBarWidthMeters = (tileWidthMeters * Float(configuration.numberOfTilesHorizontal)
            + gutterMeters * Float(configuration.numberOfTilesHorizontal - 1))
            * configuration.fovWidthScaleFactor
        timeBarLeftMeters = fovCenterMeters.x - timeBarWidthMeters / 2
        let gridHeightMeters = tileHeightMeters * Float(configuration.numberOfTilesVertical)
            + gutterMeters * Float(configuration.numberOfTilesVertical - 1)
            + innerMarginMeters * 2
        timeBarCenterYMeters = fovCenterMeters.y
            - (gridHeightMeters / 2 + backHeightMeters / 2) * configuration.fovHeightScaleFactor
        timeBarHalfHeightMeters = Self.sizeMeters(
            degrees: configuration.timeBarHeightArcmin / 60,
            distance: configuration.distanceMeters
        ) * configuration.fovHeightScaleFactor / 2
    }

    private static func sizeMeters(degrees: Float, distance: Float) -> Float {
        2 * distance * tan(degrees * .pi / 360)
    }

    private static func offsetMeters(degrees: Float, distance: Float) -> Float {
        distance * tan(degrees * .pi / 180)
    }
}

private struct TrialRenderResources: @unchecked Sendable {
    let revision: Int
    let experiment: Experiment
    let geometry: StimulusGeometry
    let maskedTexture: StimulusTexture
    let revealedTexture: StimulusTexture
    let correctHighlightTexture: StimulusTexture?
    let wrongHighlightTexture: StimulusTexture?
    let timeBarTexture: TimeBarTexture?
    let taskMode: TaskMode
}

private final class TrialResourceMailbox: @unchecked Sendable {
    enum Completion {
        case success(TrialRenderResources)
        case failure(revision: Int, message: String)
    }

    private let lock = NSLock()
    private var loadingRevision: Int?
    private var completion: Completion?

    func beginLoading(revision: Int) -> Bool {
        lock.withLock {
            guard loadingRevision != revision else { return false }
            loadingRevision = revision
            completion = nil
            return true
        }
    }

    func finish(_ result: Completion) {
        lock.withLock {
            completion = result
        }
    }

    func takeCompletion() -> Completion? {
        lock.withLock {
            guard let completion else { return nil }
            self.completion = nil
            loadingRevision = nil
            return completion
        }
    }
}

private enum RendererError: LocalizedError {
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

actor Renderer {
    private static let maxFramesInFlight = 3
    @MainActor private static var activeLayerRendererIDs = Set<ObjectIdentifier>()

    private let layerRenderer: LayerRenderer
    private let appModel: AppModel
    private var experiment: Experiment?
    private var geometry: StimulusGeometry?
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private let commandQueue: MTLCommandQueue
    private let visualPipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var maskedStimulusTexture: StimulusTexture?
    private var revealedStimulusTexture: StimulusTexture?
    private var correctHighlightStimulusTexture: StimulusTexture?
    private var wrongHighlightStimulusTexture: StimulusTexture?
    private var timeBarTexture: TimeBarTexture?
    private var taskMode: TaskMode = .fixedNumberOfTrials
    private let presentationState: StimulusPresentationState
    private let trialResourceMailbox = TrialResourceMailbox()
    private var activeTrialRevision: Int?
    private var preparedTrialResources: TrialRenderResources?
    private var failedTrialRevision: Int?
    private var participantPromptTexture: ParticipantPromptTexture?
    private var lastParticipantPrompt: StimulusPresentationState.Prompt?
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
        appModel: AppModel
    ) throws {
        DiagnosticLog.event("render", "Renderer initialization begin; device=\(layerRenderer.device.name) allocatedBytes=\(layerRenderer.device.currentAllocatedSize)")
        self.layerRenderer = layerRenderer
        self.appModel = appModel
        self.experiment = nil
        self.presentationState = appModel.stimulusPresentationState
        self.geometry = nil

        let device = layerRenderer.device
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue
        self.maskedStimulusTexture = nil
        self.revealedStimulusTexture = nil
        self.correctHighlightStimulusTexture = nil
        self.wrongHighlightStimulusTexture = nil
        self.timeBarTexture = nil

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
        } catch {
            throw RendererError.pipelineCreationFailed(error)
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        // Every SmartFOV123 primitive lies on one stimulus plane. Comparing
        // coplanar depths causes unstable z-fighting between the FOV, tiles,
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
                descriptor.label = "SmartFOV123 frame \(index)"
                descriptor.initialCapacity = 8
                return try device.makeResidencySet(descriptor: descriptor)
            }
        } catch {
            throw RendererError.residencySetCreationFailed(error)
        }

        guard let endFrameEvent = device.makeSharedEvent() else {
            throw RendererError.residencySetCreationFailed(
                NSError(
                    domain: "SmartFOV123",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Metal couldn't create a frame synchronization event."]
                )
            )
        }
        self.endFrameEvent = endFrameEvent
        #endif
        DiagnosticLog.event("render", "Renderer initialization complete; allocatedBytes=\(device.currentAllocatedSize)")
    }

    @MainActor
    static func start(_ layerRenderer: LayerRenderer, appModel: AppModel) {
        let layerRendererID = ObjectIdentifier(layerRenderer)
        guard activeLayerRendererIDs.insert(layerRendererID).inserted else {
            DiagnosticLog.event(
                "render",
                "duplicate render task launch ignored; layerRenderer=\(layerRendererID)"
            )
            return
        }

        DiagnosticLog.event("render", "render task launch requested")
        Task(executorPreference: RenderTaskExecutor.shared) {
            do {
                let renderer = try Renderer(layerRenderer, appModel: appModel)
                try await renderer.startARSession()
                await renderer.renderLoop()
            } catch {
                DiagnosticLog.event("error", "renderer stopped with error: \(error.localizedDescription)")
                await MainActor.run {
                    appModel.statusMessage = error.localizedDescription
                    appModel.immersiveSpaceState = .open
                }
            }
            _ = await MainActor.run {
                activeLayerRendererIDs.remove(layerRendererID)
            }
        }
    }

    private func startARSession() async throws {
        DiagnosticLog.event("tracking", "ARKitSession run requested")
        do {
            try await arSession.run([worldTracking])
        } catch {
            throw RendererError.arSessionFailed(error)
        }

        for _ in 0..<200 {
            if worldTracking.state == .running {
                DiagnosticLog.event("tracking", "WorldTrackingProvider running")
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
        var hasMarkedRendererRunning = false
        while true {
            updateTrialResources()

            switch layerRenderer.state {
            case .running:
                if !hasMarkedRendererRunning {
                    presentationState.markRendererRunning()
                    hasMarkedRendererRunning = true
                    DiagnosticLog.event("render", "LayerRenderer entered running state")
                }
                publishState(.open)
                autoreleasepool {
                    renderFrame()
                }
            case .paused:
                DiagnosticLog.event("render", "LayerRenderer paused; waiting to resume")
                layerRenderer.waitUntilRunning()
                DiagnosticLog.event("render", "LayerRenderer wait returned; state=\(String(describing: layerRenderer.state))")
            case .invalidated:
                DiagnosticLog.event("render", "LayerRenderer invalidated; stopping render loop")
                arSession.stop()
                publishState(.closed)
                return
            @unknown default:
                arSession.stop()
                publishState(.closed)
                return
            }
        }
    }

    private func publishState(_ state: AppModel.ImmersiveSpaceState) {
        guard lastPublishedState != state else { return }
        lastPublishedState = state
        Task { @MainActor in
            appModel.immersiveSpaceState = state
        }
    }

    private func updateTrialResources() {
        if let completion = trialResourceMailbox.takeCompletion() {
            switch completion {
            case .success(let resources):
                DiagnosticLog.event("render", "resource build completed; revision=\(resources.revision) allocatedBytes=\(layerRenderer.device.currentAllocatedSize)")
                preparedTrialResources = resources
                failedTrialRevision = nil
                presentationState.markTrialReady(revision: resources.revision)
            case .failure(let revision, let message):
                DiagnosticLog.event("error", "resource build failed; revision=\(revision) message=\(message)")
                failedTrialRevision = revision
                presentationState.markTrialReady(revision: revision)
                Task { @MainActor in
                    appModel.showConfigurationError(message)
                }
            }
        }

        if let revision = presentationState.activeRevision,
           revision != activeTrialRevision,
           let resources = preparedTrialResources,
           resources.revision == revision {
            experiment = resources.experiment
            geometry = resources.geometry
            maskedStimulusTexture = resources.maskedTexture
            revealedStimulusTexture = resources.revealedTexture
            correctHighlightStimulusTexture = resources.correctHighlightTexture
            wrongHighlightStimulusTexture = resources.wrongHighlightTexture
            timeBarTexture = resources.timeBarTexture
            taskMode = resources.taskMode
            activeTrialRevision = revision
            preparedTrialResources = nil
            loggedProjectionEyes.removeAll()
            DiagnosticLog.event("render", "resources activated; revision=\(revision) allocatedBytes=\(layerRenderer.device.currentAllocatedSize)")
        }

        guard let request = presentationState.trialRequest,
              request.revision != activeTrialRevision,
              request.revision != preparedTrialResources?.revision,
              request.revision != failedTrialRevision,
              trialResourceMailbox.beginLoading(revision: request.revision) else {
            return
        }

        let device = layerRenderer.device
        let mailbox = trialResourceMailbox
        DiagnosticLog.event("render", "resource build begin; revision=\(request.revision) trial=\(request.experiment.trialNumber) allocatedBytes=\(device.currentAllocatedSize)")
        Task.detached(priority: .userInitiated) {
            do {
                guard let textureCommandQueue = device.makeCommandQueue() else {
                    throw RendererError.commandQueueCreationFailed
                }
                let resources = try TrialRenderResources(
                    revision: request.revision,
                    experiment: request.experiment,
                    geometry: StimulusGeometry(
                        configuration: request.experiment.configuration.stimulus
                    ),
                    maskedTexture: StimulusTexture(
                        device: device,
                        commandQueue: textureCommandQueue,
                        experiment: request.experiment,
                        taskMode: request.taskMode,
                        score: request.score,
                        trialsRemaining: request.trialsRemaining,
                        presentation: .masked
                    ),
                    revealedTexture: StimulusTexture(
                        device: device,
                        commandQueue: textureCommandQueue,
                        experiment: request.experiment,
                        taskMode: request.taskMode,
                        score: request.score,
                        trialsRemaining: request.trialsRemaining,
                        presentation: .revealed
                    ),
                    correctHighlightTexture: request.experiment.configuration.stimulus
                        .digitHighlightCorrectRGB == nil
                        ? nil
                        : try StimulusTexture(
                            device: device,
                            commandQueue: textureCommandQueue,
                            experiment: request.experiment,
                            taskMode: request.taskMode,
                            score: request.score,
                            trialsRemaining: request.trialsRemaining,
                            presentation: .highlightedCorrect
                        ),
                    wrongHighlightTexture: request.experiment.configuration.stimulus
                        .digitHighlightWrongRGB == nil
                        ? nil
                        : try StimulusTexture(
                            device: device,
                            commandQueue: textureCommandQueue,
                            experiment: request.experiment,
                            taskMode: request.taskMode,
                            score: request.score,
                            trialsRemaining: request.trialsRemaining,
                            presentation: .highlightedWrong
                        ),
                    timeBarTexture: request.taskMode.durationSeconds == nil
                        ? nil
                        : try TimeBarTexture(
                            device: device,
                            commandQueue: textureCommandQueue,
                            configuration: request.experiment.configuration
                        ),
                    taskMode: request.taskMode
                )
                mailbox.finish(.success(resources))
                DiagnosticLog.event("render", "resource build queued for activation; revision=\(request.revision) allocatedBytes=\(device.currentAllocatedSize)")
            } catch {
                DiagnosticLog.event("error", "resource construction threw; revision=\(request.revision) error=\(error.localizedDescription)")
                mailbox.finish(
                    .failure(
                        revision: request.revision,
                        message: "The next trial couldn't be rendered: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    private func publishError(_ message: String) {
        Task { @MainActor in
            appModel.statusMessage = message
        }
    }

    private func renderFrame() {
        // Narrow the interval between checking the compositor state and asking
        // for a frame. xrOS 27 beta 6 has aborted inside queryNextFrame() when
        // the layer transitions away from running between render-loop steps.
        guard case .running = layerRenderer.state else { return }

        guard let frame = layerRenderer.queryNextFrame() else {
            Thread.sleep(forTimeInterval: 0.001)
            return
        }

        // Compositor Services requires timing prediction before the update
        // phase begins. At this point no frame phase has started, so Apple's
        // documented render-loop pattern permits abandoning a frame for which
        // timing is unavailable.
        guard let timing = frame.predictTiming() else { return }

        // Resolve fallible Metal prerequisites before beginning the compositor
        // frame phases. Once startUpdate() runs below, this function proceeds
        // through submission unless Compositor Services itself supplies no
        // drawable, which its documented render-loop pattern permits.
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

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            publishError("Metal couldn't create a frame command buffer.")
            return
        }
        commandBuffer.label = "SmartFOV123 frame"

        frame.startUpdate()
        frame.endUpdate()
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)

        // Apple's Compositor Services render-loop contract starts submission
        // before querying drawables. If no drawable is available, abandon this
        // frame without calling endSubmission(), matching Apple's sample. A
        // nonempty result must always proceed through commit/endSubmission.
        frame.startSubmission()

        let drawables: [LayerRenderer.Drawable]
        if #available(visionOS 26.0, *) {
            drawables = frame.queryDrawables()
        } else if let drawable = frame.queryDrawable() {
            drawables = [drawable]
        } else {
            drawables = []
        }
        guard !drawables.isEmpty else { return }

        var hasDeviceAnchor = false
        for drawable in drawables {
            // The drawable carries the compositor's latest presentation time.
            // Anchor assignment is optional. If tracking is transiently
            // unavailable, leave the anchor unset and still complete this
            // frame's submission lifecycle.
            guard let deviceAnchor = worldTracking.queryDeviceAnchor(
                atTimestamp: drawable.frameTiming.presentationTime.timeInterval
            ) else { continue }
            drawable.deviceAnchor = deviceAnchor
            hasDeviceAnchor = true
        }
        if hasDeviceAnchor {
            clearDeviceTrackingWaitIfNeeded()
        } else {
            publishDeviceTrackingWaitIfNeeded()
        }
        let surfaceTexture: MTLTexture?
        let presentationContent = presentationState.content
        let rendersSurface: Bool
        let rendersTimeBar: Bool
        let rendersBinocularly: Bool
        let surfaceCenter: SIMD2<Float>
        let surfaceHalfSize: SIMD2<Float>
        let surfaceDistance: Float
        switch presentationContent {
        case .hidden:
            surfaceTexture = maskedStimulusTexture?.texture
            rendersSurface = false
            rendersTimeBar = false
            rendersBinocularly = false
            surfaceCenter = geometry?.fovCenterMeters ?? .zero
            surfaceHalfSize = geometry?.fovHalfSizeMeters ?? .zero
            surfaceDistance = geometry?.distanceMeters ?? 1.5
        case .participantPrompt(let prompt):
            if prompt != lastParticipantPrompt || participantPromptTexture == nil {
                do {
                    participantPromptTexture = try ParticipantPromptTexture(
                        device: layerRenderer.device,
                        commandQueue: commandQueue,
                        prompt: prompt
                    )
                    lastParticipantPrompt = prompt
                } catch {
                    publishError("The participant dialog couldn't be rendered: \(error.localizedDescription)")
                }
            }
            surfaceTexture = participantPromptTexture?.texture
            rendersSurface = participantPromptTexture != nil
            rendersTimeBar = false
            rendersBinocularly = true
            surfaceCenter = .zero
            surfaceHalfSize = participantPromptTexture?.halfSizeMeters ?? SIMD2<Float>(0.465, 0.332)
            surfaceDistance = 1.5
        case .maskedGrid:
            surfaceTexture = maskedStimulusTexture?.texture
            rendersSurface = maskedStimulusTexture != nil && geometry != nil
            rendersTimeBar = true
            rendersBinocularly = false
            surfaceCenter = geometry?.fovCenterMeters ?? .zero
            surfaceHalfSize = geometry?.fovHalfSizeMeters ?? .zero
            surfaceDistance = geometry?.distanceMeters ?? 1.5
        case .revealedGrid:
            surfaceTexture = revealedStimulusTexture?.texture
            rendersSurface = revealedStimulusTexture != nil && geometry != nil
            rendersTimeBar = true
            rendersBinocularly = false
            surfaceCenter = geometry?.fovCenterMeters ?? .zero
            surfaceHalfSize = geometry?.fovHalfSizeMeters ?? .zero
            surfaceDistance = geometry?.distanceMeters ?? 1.5
        case .highlightedGrid(let correct):
            let highlightTexture = correct
                ? correctHighlightStimulusTexture
                : wrongHighlightStimulusTexture
            surfaceTexture = highlightTexture?.texture
            rendersSurface = highlightTexture != nil && geometry != nil
            rendersTimeBar = true
            rendersBinocularly = false
            surfaceCenter = geometry?.fovCenterMeters ?? .zero
            surfaceHalfSize = geometry?.fovHalfSizeMeters ?? .zero
            surfaceDistance = geometry?.distanceMeters ?? 1.5
        }

        #if !targetEnvironment(simulator)
        if let surfaceTexture {
            residencySet.addAllocation(surfaceTexture)
        }
        if let timeBarTexture {
            residencySet.addAllocation(timeBarTexture.texture)
        }
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

        for drawable in drawables {
            render(
                drawable,
                into: commandBuffer,
                surfaceTexture: surfaceTexture,
                rendersSurface: rendersSurface,
                rendersTimeBar: rendersTimeBar,
                rendersBinocularly: rendersBinocularly,
                surfaceCenter: surfaceCenter,
                surfaceHalfSize: surfaceHalfSize,
                surfaceDistance: surfaceDistance
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
        surfaceTexture: MTLTexture?,
        rendersSurface: Bool,
        rendersTimeBar: Bool,
        rendersBinocularly: Bool,
        surfaceCenter: SIMD2<Float>,
        surfaceHalfSize: SIMD2<Float>,
        surfaceDistance: Float
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
            if drawable.rasterizationRateMaps.indices.contains(textureMap.textureIndex) {
                descriptor.rasterizationRateMap = drawable.rasterizationRateMaps[textureMap.textureIndex]
            }

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                publishError("Metal couldn't create a render encoder.")
                continue
            }

            encoder.label = viewIndex == 0 ? "SmartFOV123 left view" : "SmartFOV123 right view"
            encoder.setViewport(textureMap.viewport)
            encoder.setRenderPipelineState(visualPipelineState)
            encoder.setDepthStencilState(depthState)
            if let surfaceTexture {
                encoder.setFragmentTexture(surfaceTexture, index: 0)
            }

            let clipFromDevice = drawable.computeProjection(viewIndex: viewIndex) * view.transform.inverse
            logProjectionMetricsIfNeeded(
                viewIndex: viewIndex,
                viewTransform: view.transform,
                clipFromDevice: clipFromDevice,
                viewport: textureMap.viewport
            )
            if surfaceTexture != nil,
               rendersSurface,
               (rendersBinocularly
                    || shouldRenderStimulus(viewIndex: viewIndex, viewTransform: view.transform)) {
                drawTexturedQuad(
                    encoder: encoder,
                    clipFromDevice: clipFromDevice,
                    center: surfaceCenter,
                    halfSize: surfaceHalfSize,
                    distance: surfaceDistance
                )
            }
            if rendersTimeBar,
               case .loopTrials = taskMode,
               let timeBarTexture,
               let geometry,
               (rendersBinocularly
                    || shouldRenderStimulus(viewIndex: viewIndex, viewTransform: view.transform)) {
                let fraction = min(max(presentationState.timeBarFillFraction, 0), 1)
                let width = geometry.timeBarWidthMeters * fraction
                if width > 0 {
                    encoder.setFragmentTexture(timeBarTexture.texture, index: 0)
                    drawTexturedQuad(
                        encoder: encoder,
                        clipFromDevice: clipFromDevice,
                        center: SIMD2(
                            geometry.timeBarLeftMeters + width / 2,
                            geometry.timeBarCenterYMeters
                        ),
                        halfSize: SIMD2(width / 2, geometry.timeBarHalfHeightMeters),
                        distance: geometry.distanceMeters,
                        uvMaxX: fraction
                    )
                }
            }
            encoder.endEncoding()
        }
    }

    private func shouldRenderStimulus(
        viewIndex: Int,
        viewTransform: simd_float4x4
    ) -> Bool {
        guard let experiment else { return false }
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

        guard let geometry, let experiment else { return }
        let halfHeight = geometry.digitHeightMeters / 2
        let bottom = clipFromDevice * SIMD4<Float>(
            geometry.fovCenterMeters.x,
            geometry.fovCenterMeters.y - halfHeight,
            -geometry.distanceMeters,
            1
        )
        let top = clipFromDevice * SIMD4<Float>(
            geometry.fovCenterMeters.x,
            geometry.fovCenterMeters.y + halfHeight,
            -geometry.distanceMeters,
            1
        )
        guard bottom.w != 0, top.w != 0 else { return }
        let normalizedDeviceHeight = abs(top.y / top.w - bottom.y / bottom.w)
        let projectedPixelHeight = Double(normalizedDeviceHeight) * viewport.height / 2
        let configuredArcminutes = experiment.configuration.stimulus.digitHeightArcmin
        print(
            String(
                format: "SmartFOV123: %@ eye viewport %.0f x %.0f; %.1f arcmin digit cap height projects to %.2f pixels.",
                eyeLabel,
                viewport.width,
                viewport.height,
                configuredArcminutes,
                projectedPixelHeight
            )
        )
    }

    private func drawTexturedQuad(
        encoder: MTLRenderCommandEncoder,
        clipFromDevice: simd_float4x4,
        center: SIMD2<Float>,
        halfSize: SIMD2<Float>,
        distance: Float,
        uvMaxX: Float = 1
    ) {
        var uniforms = StimulusUniforms(
            clipFromDevice: clipFromDevice,
            centerMeters: center,
            halfSizeMeters: halfSize,
            distanceMeters: distance,
            uvMaxX: uvMaxX
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
        DiagnosticLog.event(
            "tracking",
            "device anchor unavailable; submitting frame without pose correction"
        )
        publishError("Headset tracking is temporarily unavailable; rendering without pose correction.")
    }

    private func clearDeviceTrackingWaitIfNeeded() {
        guard isWaitingForDeviceTracking else { return }
        isWaitingForDeviceTracking = false
        DiagnosticLog.event("tracking", "device anchor restored")
        Task { @MainActor in
            if appModel.statusMessage == "Headset tracking is temporarily unavailable; rendering without pose correction." {
                appModel.statusMessage = nil
            }
        }
    }
}
