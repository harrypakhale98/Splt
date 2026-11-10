import SpltCore
import Foundation

/// Connects the group screens to sync. When iCloud sharing is available the invite link is the
/// share's own link, otherwise it is the plain `splt://` link that `LocalGroupSharing` makes.
struct SyncGroupSharing: GroupSharing {
    private let runtime: SyncRuntime

    @MainActor
    init(runtime: SyncRuntime = .shared) {
        self.runtime = runtime
    }

    func inviteURL(for groupID: GroupID, groupName: String) async throws -> URL {
        let local = try await LocalGroupSharing().inviteURL(for: groupID, groupName: groupName)
        return try await Self.shareURL(for: groupID, runtime: runtime) ?? local
    }

    func leave(groupID: GroupID) async throws {
        try await Self.leave(groupID, runtime: runtime)
    }

    @MainActor
    private static func shareURL(for groupID: GroupID, runtime: SyncRuntime) async throws -> URL? {
        guard runtime.status.isConnected else { return nil }
        do {
            return try await runtime.engine.share(group: groupID, anyoneWithLink: true).url
        } catch SyncError.unavailable {
            return nil
        }
    }

    @MainActor
    private static func leave(_ groupID: GroupID, runtime: SyncRuntime) async throws {
        guard runtime.status.isConnected else { return }
        try await runtime.engine.leave(group: groupID)
    }
}
