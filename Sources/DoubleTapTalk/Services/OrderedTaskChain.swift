import Foundation

/// Serial execution chain: every enqueued operation waits for the previously
/// enqueued one, so operations run strictly in enqueue order regardless of how
/// long each takes or which thread enqueued it. Thread-safe.
///
/// Used by relay dictation to guarantee that rotated segments are delivered in
/// order (and that `drain()` waits for all of them before the final segment is
/// enqueued), and by the app delegate to serialize per-segment cloud ASR +
/// refinement + injection.
final class OrderedTaskChain {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?
    /// Monotonic count of enqueued operations — lets `drain()` tell whether
    /// something new appeared while it was waiting.
    private var enqueuedCount = 0

    /// Appends `operation`: it runs after every previously enqueued operation,
    /// without blocking the caller.
    func enqueue(_ operation: @escaping () async -> Void) {
        lock.lock()
        let previous = tail
        tail = Task {
            _ = await previous?.value
            await operation()
        }
        enqueuedCount += 1
        lock.unlock()
    }

    /// The operation currently at the tail, or nil when nothing was enqueued.
    var lastOperation: Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return tail
    }

    /// Waits for everything enqueued so far. Since each operation awaits its
    /// predecessor, awaiting the tail is enough to order everything before it;
    /// the count re-check covers work appended while this is waiting.
    func drain() async {
        while true {
            lock.lock()
            let task = tail
            let count = enqueuedCount
            lock.unlock()

            guard let task else { return }
            _ = await task.value

            lock.lock()
            let nothingNew = enqueuedCount == count
            lock.unlock()
            if nothingNew { return }
        }
    }
}