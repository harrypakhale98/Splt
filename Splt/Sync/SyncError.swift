import Foundation

/// Why a sync request could not be carried out.
enum SyncError: LocalizedError, Equatable, Sendable {
    /// This build or this account cannot sync.
    case unavailable
    case groupNotFound
    /// The group was never shared, so there is nothing to leave.
    case notShared
    case invalidInvitation
    /// Sync is still starting or the account is not ready.
    case notReady
    /// The group is shared invite-only and only its owner can open the link to anyone.
    case linkNotOpen
    /// The system invite sheet is only for the person who shared the group.
    case ownerInvites
    /// Nobody is signed in to iCloud, so an invitation cannot be accepted.
    case noAccount
    /// iCloud is restricted on this device, so an invitation cannot be accepted.
    case restricted
    /// The group stayed on the device after a switch to another iCloud account and is never uploaded.
    case notInThisAccount

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "iCloud sync is not available in this build.")
        case .groupNotFound:
            String(localized: "That group could not be found.")
        case .notShared:
            String(localized: "This group is not shared.")
        case .invalidInvitation:
            String(localized: "This invitation is not valid any more. Ask for a new one.")
        case .notReady:
            String(localized: "Sync is still getting ready. Try again in a moment.")
        case .linkNotOpen:
            String(localized: "Only the person who shared this group can make a link anyone can join.")
        case .ownerInvites:
            String(localized: "Only the person who shared this group can invite people with iCloud.")
        case .noAccount:
            String(localized: "Sign in to iCloud in the Settings app, then open the invitation again.")
        case .restricted:
            String(localized: "iCloud is restricted on this device, so shared groups cannot be joined here.")
        case .notInThisAccount:
            String(localized: "This group stayed on this device when you switched iCloud accounts. It is not in your iCloud, so it cannot be shared.")
        }
    }
}
