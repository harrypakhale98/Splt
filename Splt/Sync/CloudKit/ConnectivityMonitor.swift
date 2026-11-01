import Foundation
import Network

/// Tells whether the device has a network path, so Settings can say "Offline" before a request fails.
final class ConnectivityMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "splt.sync.connectivity")

    /// Yields the current state first and then every change.
    func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { [monitor] _ in monitor.cancel() }
            monitor.start(queue: queue)
        }
    }
}
