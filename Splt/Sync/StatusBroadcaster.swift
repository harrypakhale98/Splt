import Foundation

/// Keeps the latest status and fans it out to any number of listeners.
@MainActor
final class StatusBroadcaster {
    private(set) var current: SyncStatus
    private var listeners: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]

    init(initial: SyncStatus = .idle) {
        current = initial
    }

    func updates() -> AsyncStream<SyncStatus> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SyncStatus>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.yield(current)
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.listeners[id] = nil }
        }
        return stream
    }

    /// Returns true when the status actually changed.
    @discardableResult
    func send(_ status: SyncStatus) -> Bool {
        guard status != current else { return false }
        current = status
        for continuation in listeners.values {
            continuation.yield(status)
        }
        return true
    }
}
