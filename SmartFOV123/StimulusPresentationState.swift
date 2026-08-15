import Foundation

final class StimulusPresentationState: @unchecked Sendable {
    struct TrialRequest: Sendable {
        let revision: Int
        let experiment: Experiment
        let trialsRemaining: Int
    }

    struct Prompt: Equatable, Sendable {
        let title: String
        let message: String
        let emphasizedText: String?
        let usesLeadingAlignment: Bool
    }

    enum Content: Equatable, Sendable {
        case hidden
        case participantPrompt(Prompt)
        case maskedGrid
        case revealedGrid
    }

    private let lock = NSLock()
    private var currentContent: Content = .hidden
    private var currentTrialRequest: TrialRequest?
    private var nextTrialRevision = 1
    private var readyTrialRevision: Int?

    var content: Content {
        lock.withLock { currentContent }
    }

    var trialRequest: TrialRequest? {
        lock.withLock { currentTrialRequest }
    }

    func prepareTrial(experiment: Experiment, trialsRemaining: Int) -> Int {
        lock.withLock {
            let revision = nextTrialRevision
            nextTrialRevision += 1
            currentTrialRequest = .init(
                revision: revision,
                experiment: experiment,
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

    func hide() {
        lock.withLock {
            currentContent = .hidden
        }
    }
}
