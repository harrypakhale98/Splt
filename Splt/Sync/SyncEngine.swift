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
/// After joining from an invite page, who the person joining takes over: someone added by name the
/// invite was made for, or whoever they pick from those still waiting.
enum JoinAs: Hashable, Sendable {
    case person(PersonID)
    case askWho
}

struct ShareInvitation: @unchecked Sendable {
    let metadata: CKShare.Metadata?
    let groupName: String?
    /// An iCloud invite link whose metadata is fetched before accepting, for a link that came from
    /// Splt's own invite page instead of the system.
    let shareURL: URL?
    /// Who the person joining becomes: the one the invite was made for, or whoever they pick.
    let claim: JoinAs?

    init(metadata: CKShare.Metadata, claim: JoinAs? = nil) {
        self.metadata = metadata
        self.groupName = nil
        self.shareURL = nil
        self.claim = claim
    }

    /// An invite link from Splt's invite page, made for one person.
    init(shareURL: URL, claim: JoinAs?) {
        self.metadata = nil
        self.groupName = nil
        self.shareURL = shareURL
        self.claim = claim
    }

    /// An invitation without CloudKit metadata, for fakes and tests.
    init(groupName: String?) {
        self.metadata = nil
        self.groupName = groupName
        self.shareURL = nil
        self.claim = nil
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
    /// Reads an iCloud invite link, as the system does when someone taps one.
    func shareMetadata(for url: URL) async throws -> CKShare.Metadata
    /// Leaves a group someone else shared. A group in your own iCloud is not affected.
    func leave(group: GroupID) async throws
    /// True when the group is in your own iCloud and shared with others. Stopping is done in the invite
    /// sheet, or by deleting the group. With no network the last known answer is used.
    func isSharedByMe(group: GroupID) async -> Bool
    /// The groups other people shared with you, as last known. You leave those; your own you delete.
    var groupsSharedWithMe: Set<GroupID> { get }
    /// True once this device has fetched everything iCloud holds, on this launch or an earlier one.
    /// Until then groups from iCloud may still be on their way. True for an engine that does not sync.
    var hasFetchedOnce: Bool { get }
}

extension SyncEngine {
    var hasFetchedOnce: Bool { true }

    func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        throw SyncError.unavailable
    }
}
