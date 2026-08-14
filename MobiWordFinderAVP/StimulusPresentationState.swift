import Foundation

final class StimulusPresentationState: @unchecked Sendable {
    private let lock = NSLock()
    private var isGridRevealed = false

    var showsDigits: Bool {
        lock.withLock { isGridRevealed }
    }

    func reset() {
        lock.withLock {
            isGridRevealed = false
        }
    }

    func revealGrid() {
        lock.withLock {
            isGridRevealed = true
        }
    }
}
