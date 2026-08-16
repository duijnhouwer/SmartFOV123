import Foundation

final class StimulusPresentationState: @unchecked Sendable {
    struct TrialRequest: Sendable {
        let revision: Int
        let experiment: Experiment
        let taskMode: TaskMode
        let score: Int
        let trialsRemaining: Int
    }

    struct Prompt: Equatable, Sendable {
        let title: String
        let message: String
        let usesLeadingAlignment: Bool
    }

    enum Content: Equatable, Sendable {
        case hidden
        case participantPrompt(Prompt)
        case maskedGrid
        case revealedGrid
        case highlightedGrid
    }

    private let lock = NSLock()
    private var currentContent: Content = .hidden
    private var currentTrialRequest: TrialRequest?
    private var nextTrialRevision = 1
    private var readyTrialRevision: Int?
    private var activeTrialRevision: Int?
    private var rendererRunning = false
    private var timeBarStartUptimeNanoseconds: UInt64?
    private var timeBarDurationNanoseconds: UInt64?

    var content: Content {
        lock.withLock { currentContent }
    }

    var trialRequest: TrialRequest? {
        lock.withLock { currentTrialRequest }
    }

    var isRendererRunning: Bool {
        lock.withLock { rendererRunning }
    }

    var activeRevision: Int? {
        lock.withLock { activeTrialRevision }
    }

    var timeBarFillFraction: Float {
        lock.withLock {
            guard let start = timeBarStartUptimeNanoseconds,
                  let duration = timeBarDurationNanoseconds, duration > 0 else { return 1 }
            let now = DispatchTime.now().uptimeNanoseconds
            let elapsed = now >= start ? now - start : 0
            return Float(max(0, 1 - Double(elapsed) / Double(duration)))
        }
    }

    func startTimeBar(durationSeconds: Int) {
        lock.withLock {
            timeBarStartUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
            timeBarDurationNanoseconds = UInt64(durationSeconds) * 1_000_000_000
        }
    }

    func stopTimeBar() {
        lock.withLock {
            timeBarStartUptimeNanoseconds = nil
            timeBarDurationNanoseconds = nil
        }
    }

    func markRendererRunning() {
        lock.withLock {
            rendererRunning = true
        }
    }

    func prepareTrial(
        experiment: Experiment,
        taskMode: TaskMode,
        score: Int,
        trialsRemaining: Int
    ) -> Int {
        lock.withLock {
            let revision = nextTrialRevision
            nextTrialRevision += 1
            currentTrialRequest = .init(
                revision: revision,
                experiment: experiment,
                taskMode: taskMode,
                score: score,
                trialsRemaining: trialsRemaining
            )
            readyTrialRevision = nil
            return revision
        }
    }

    func markTrialReady(revision: Int) {
        lock.withLock {
            guard currentTrialRequest?.revision == revision else { return }
            readyTrialRevision = revision
        }
    }

    func isTrialReady(revision: Int) -> Bool {
        lock.withLock { readyTrialRevision == revision }
    }

    func reset() {
        lock.withLock {
            guard let revision = readyTrialRevision,
                  currentTrialRequest?.revision == revision else { return }
            activeTrialRevision = revision
            currentContent = .maskedGrid
        }
    }

    func showParticipantPrompt(_ prompt: Prompt) {
        lock.withLock {
            currentContent = .participantPrompt(prompt)
        }
    }

    func revealGrid() {
        lock.withLock {
            currentContent = .revealedGrid
        }
    }

    func highlightSolution() {
        lock.withLock {
            currentContent = .highlightedGrid
        }
    }

    func hide() {
        lock.withLock {
            currentContent = .hidden
        }
    }
}
