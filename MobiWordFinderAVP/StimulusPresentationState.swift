import Foundation

final class StimulusPresentationState: @unchecked Sendable {
    enum Content: Equatable, Sendable {
        case hidden
        case maskedGrid
        case revealedGrid
    }

    private let lock = NSLock()
    private var currentContent: Content = .maskedGrid

    var content: Content {
        lock.withLock { currentContent }
    }

    func reset() {
        lock.withLock {
            currentContent = .maskedGrid
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
