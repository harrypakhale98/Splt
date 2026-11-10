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
    /// True when anyone with the link can join, not only the people invited by name.
    var isOpenToAnyoneWithLink: Bool { share.publicPermission != .none }
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
    /// Prepares the group for the invite sheet, creating the share on first use. With
    /// `anyoneWithLink` the owner's share is opened so its link works for anyone who has it.
    /// Someone who joined the group only gets its share with `anyoneWithLink`, for the link.
    func share(group: GroupID, anyoneWithLink: Bool) async throws -> GroupShare
    /// True when the group is in your own iCloud, already shared, and only invited people can join.
    /// Sharing it with `anyoneWithLink` would open it, so the link screen asks before it does.
    func isSharedInviteOnly(group: GroupID) async throws -> Bool
    func accept(_ invitation: ShareInvitation) async throws
    /// Leaves a group someone else shared. A group in your own iCloud is not affected.
    func leave(group: GroupID) async throws
    /// True when the group is in your own iCloud and shared with others. Stopping is done in the invite
    /// sheet, or by deleting the group. With no network the last known answer is used.
    func isSharedByMe(group: GroupID) async -> Bool
    /// The groups other people shared with you, as last known. You leave those; your own you delete.
    var groupsSharedWithMe: Set<GroupID> { get }
}
