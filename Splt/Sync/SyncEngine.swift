import CloudKit
import Foundation
import SpltCore

/// A group ready to be handed to the system invite sheet.
struct GroupShare {
    let share: CKShare
    let container: CKContainer
    let groupName: String

    /// The link people can open to join, once the share is saved.
    var url: URL? { share.url }
}

/// An invitation a person opened, as the system hands it to the app.
struct ShareInvitation: @unchecked Sendable {
    let metadata: CKShare.Metadata?
    let groupName: String?

    init(metadata: CKShare.Metadata) {
        self.metadata = metadata
        self.groupName = nil
    }

    /// An invitation without CloudKit metadata, for fakes and tests.
    init(groupName: String?) {
        self.metadata = nil
        self.groupName = groupName
    }
}

/// What the app asks of sync. The CloudKit engine implements it for signed builds and
/// the no-op engine keeps the simulator, previews, tests and unsigned builds fully offline.
@MainActor
protocol SyncEngine: AnyObject {
    var status: SyncStatus { get }
    /// Yields the current status first, then every change.
    var statusUpdates: AsyncStream<SyncStatus> { get }

    func start() async
    func stop() async
    /// Uploads local changes now instead of waiting for the system to schedule it.
    func sendChanges() async throws
    /// Downloads remote changes now.
    func fetchChanges() async throws
    /// Prepares the group for the invite sheet, creating the share on first use.
    func share(group: GroupID) async throws -> GroupShare
    func accept(_ invitation: ShareInvitation) async throws
    /// Leaves a group someone else shared. A group in your own iCloud is not affected.
    func leave(group: GroupID) async throws
    /// True when the group is in your own iCloud and shared with others. Stopping is done in the invite
    /// sheet, or by deleting the group. With no network the last known answer is used.
    func isSharedByMe(group: GroupID) async -> Bool
}
