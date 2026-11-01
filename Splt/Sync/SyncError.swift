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
        }
    }
}
