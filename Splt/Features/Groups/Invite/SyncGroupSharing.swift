import SpltCore
import Foundation

/// Connects the group screens to sync.
struct SyncGroupSharing: GroupSharing {
    private let runtime: SyncRuntime

    @MainActor
    init(runtime: SyncRuntime = .shared) {
        self.runtime = runtime
    }

    func leave(groupID: GroupID) async throws {
        try await Self.leave(groupID, runtime: runtime)
    }

    func isSharedByMe(groupID: GroupID) async -> Bool {
        await Self.isSharedByMe(groupID, runtime: runtime)
    }

    @MainActor
    private static func isSharedByMe(_ groupID: GroupID, runtime: SyncRuntime) async -> Bool {
        await runtime.engine.isSharedByMe(group: groupID)
    }

    @MainActor
    private static func leave(_ groupID: GroupID, runtime: SyncRuntime) async throws {
        do {
            try await runtime.engine.leave(group: groupID)
        } catch SyncError.unavailable {
            // nothing syncs here, so there is nothing to leave
        }
    }
}
