import Foundation
import Synchronization
@testable import Splt

/// A store that lives only in memory.
final class InMemorySyncStateStore: SyncStateStore {
    private struct Contents {
        var metadata = SyncMetadata()
        var states: [DatabaseScope: Data] = [:]
    }

    private let contents = Mutex(Contents())

    func loadMetadata() -> SyncMetadata {
        contents.withLock { $0.metadata }
    }

    func saveMetadata(_ metadata: SyncMetadata) {
        contents.withLock { $0.metadata = metadata }
    }

    func loadEngineState(_ scope: DatabaseScope) -> Data? {
        contents.withLock { $0.states[scope] }
    }

    func saveEngineState(_ data: Data?, scope: DatabaseScope) {
        contents.withLock { $0.states[scope] = data }
    }

    func reset() {
        contents.withLock { $0 = Contents() }
    }
}
