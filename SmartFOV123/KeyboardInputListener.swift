import GameController
import Foundation

enum ExperimentKey: Sendable {
    case digit(Character)
    case delete
    case enter
    case space
    case other(String)

    var logName: String {
        switch self {
        case .digit(let digit): return String(digit)
        case .delete: return "delete"
        case .enter: return "enter"
        case .space: return "space"
        case .other(let name): return name
        }
    }
}

final class KeyboardInputListener {
    private let onKey: @MainActor (ExperimentKey) -> Void
    private var observers: [NSObjectProtocol] = []
    private let pressedKeysLock = NSLock()
    private var pressedKeys: Set<GCKeyCode> = []

    init(onKey: @escaping @MainActor (ExperimentKey) -> Void) {
        self.onKey = onKey
    }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCKeyboardDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.attachKeyboard()
        })
        attachKeyboard()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
        pressedKeysLock.withLock { pressedKeys.removeAll() }
    }

    private func attachKeyboard() {
        pressedKeysLock.withLock { pressedKeys.removeAll() }
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            guard let self, self.shouldEmitKeyDown(keyCode, pressed: pressed) else { return }
            let key = Self.experimentKey(for: keyCode)
            Task { @MainActor in self.onKey(key) }
        }
    }

    private func shouldEmitKeyDown(_ keyCode: GCKeyCode, pressed: Bool) -> Bool {
        pressedKeysLock.withLock {
            if pressed {
                return pressedKeys.insert(keyCode).inserted
            }
            pressedKeys.remove(keyCode)
            return false
        }
    }

    private static func experimentKey(for keyCode: GCKeyCode) -> ExperimentKey {
        switch keyCode {
        case .zero: return .digit("0")
        case .one: return .digit("1")
        case .two: return .digit("2")
        case .three: return .digit("3")
        case .four: return .digit("4")
        case .five: return .digit("5")
        case .six: return .digit("6")
        case .seven: return .digit("7")
        case .eight: return .digit("8")
        case .nine: return .digit("9")
        case .deleteOrBackspace: return .delete
        case .returnOrEnter: return .enter
        case .spacebar: return .space
        default: return .other("key_code_\(keyCode)")
        }
    }
}
