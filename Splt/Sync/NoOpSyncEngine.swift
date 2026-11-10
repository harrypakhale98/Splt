import Foundation
import Observation
import SpltCore

/// The engine for builds that cannot sync. Everything stays on the device and nothing throws on start.
@MainActor
@Observable
final class NoOpSyncEngine: SyncEngine {
    private(set) var status: SyncStatus
    @ObservationIgnored private let broadcaster: StatusBroadcaster

    init(reason: NoOpReason = .missingEntitlement) {
        let status = reason.status
        self.status = status
        self.broadcaster = StatusBroadcaster(initial: status)
    }

    var statusUpdates: AsyncStream<SyncStatus> { broadcaster.updates() }

    func start() async {}
    func stop() async {}
    func sendChanges() async throws {}
    func fetchChanges() async throws {}

    func share(group: GroupID, anyoneWithLink: Bool) async throws -> GroupShare {
        throw SyncError.unavailable
    }

    func isSharedInviteOnly(group: GroupID) async throws -> Bool {
        throw SyncError.unavailable
    }

    func accept(_ invitation: ShareInvitation) async throws {
        throw SyncError.unavailable
    }

    func leave(group: GroupID) async throws {
        throw SyncError.unavailable
    }

    func isSharedByMe(group: GroupID) async -> Bool { false }
}
