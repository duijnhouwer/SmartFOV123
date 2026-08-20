import Dispatch
import Foundation

/// Copyable, event-level diagnostics for long headset runs. Deliberately avoid
/// calling this from per-frame or per-audio-buffer callbacks.
enum DiagnosticLog {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        let startNanoseconds = DispatchTime.now().uptimeNanoseconds
        var sequence: UInt64 = 0
    }

    private static let state = State()

    static func event(_ category: String, _ message: String) {
        let now = DispatchTime.now().uptimeNanoseconds
        state.lock.withLock {
            state.sequence &+= 1
            let elapsed = now >= state.startNanoseconds
                ? Double(now - state.startNanoseconds) / 1_000_000_000
                : 0
            print(
                String(
                    format: "SmartFOV123 TRACE %06llu +%8.3fs [%@] %@",
                    state.sequence,
                    elapsed,
                    category,
                    message
                )
            )
        }
    }
}
