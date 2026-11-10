import CloudKit
import Foundation

/// How the engine should react to a CloudKit error, whatever call it came from.
enum SyncFailure: Equatable, Sendable {
    /// The server has a newer version of the record. Merge and send again.
    case conflict
    /// The record zone does not exist on the server (yet).
    case zoneMissing
    /// The server no longer has the record we hold system fields for.
    case itemMissing
    /// The network or service is busy. Keep the change and try again later.
    case transient(retryAfter: TimeInterval?)
    case offline
    case quotaExceeded
    case noAccount
    case restricted
    /// The share was removed or the permission is read only.
    case noPermission
    /// Anything else. The text is friendly and the change is kept.
    case other(String)

    init(_ error: any Error) {
        guard let cloudError = error as? CKError else {
            self = .other(Self.genericMessage)
            return
        }
        switch cloudError.code {
        case .serverRecordChanged: self = .conflict
        case .zoneNotFound, .userDeletedZone: self = .zoneMissing
        case .unknownItem: self = .itemMissing
        case .networkUnavailable, .networkFailure: self = .offline
        // an account that is signed in but not ready yet is a wait, not a missing account
        case .serviceUnavailable, .zoneBusy, .requestRateLimited, .limitExceeded, .serverResponseLost, .batchRequestFailed,
             .accountTemporarilyUnavailable:
            self = .transient(retryAfter: cloudError.retryAfterSeconds)
        case .quotaExceeded: self = .quotaExceeded
        case .notAuthenticated: self = .noAccount
        case .managedAccountRestricted: self = .restricted
        case .permissionFailure: self = .noPermission
        default: self = .other(Self.genericMessage)
        }
    }

    static let genericMessage = String(localized: "Sync ran into a problem. Your changes are safe on this device and will be sent later.")

    /// What Settings should show, or nil when the failure does not need to be surfaced.
    /// For a failure that has no database, such as one at start, this is the wording for your own iCloud.
    var status: SyncStatus? { status(in: .privateDatabase) }

    /// The same for a failure from one database. A group someone else shared is stored in their iCloud,
    /// so full storage there is theirs to fix.
    func status(in scope: DatabaseScope) -> SyncStatus? {
        switch self {
        case .conflict, .zoneMissing, .itemMissing, .transient: nil
        case .offline: .offline
        case .quotaExceeded:
            switch scope {
            case .privateDatabase:
                .error(String(localized: "Your iCloud storage is full. Free up space or buy more in Settings and Splt will finish syncing. Your changes are safe on this device."))
            case .sharedDatabase:
                .error(String(localized: "The group owner's iCloud storage is full. Your changes are safe on this device and will sync once they free up space."))
            }
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .noPermission:
            .error(String(localized: "You no longer have permission to change a shared group. Your changes are kept on this device."))
        case .other(let message): .error(message)
        }
    }

    /// True when waiting and trying again can help.
    var isRetryable: Bool {
        switch self {
        case .transient, .offline, .quotaExceeded, .noAccount, .noPermission, .other: true
        case .conflict, .zoneMissing, .itemMissing, .restricted: false
        }
    }

    var retryAfter: TimeInterval? {
        if case .transient(let seconds) = self { seconds } else { nil }
    }
}

extension SyncFailure {
    /// Plain words for an alert when something the person asked for failed, such as joining or inviting.
    /// `status` talks about changes waiting to sync, which is not what went wrong here.
    static func message(for error: any Error) -> String {
        if let known = error as? SyncError { return known.localizedDescription }
        switch SyncFailure(error) {
        case .offline:
            return String(localized: "You are offline. Try again when you are back online.")
        case .noAccount:
            return SyncStatus.noAccount.detail
        case .restricted:
            return SyncStatus.restricted.detail
        case .quotaExceeded:
            return String(localized: "Your iCloud storage is full. Free up space and try again.")
        case .noPermission:
            return String(localized: "You do not have permission to do that in this group.")
        case .zoneMissing, .itemMissing:
            return String(localized: "That group could not be found in iCloud. It may have been deleted or is no longer shared.")
        case .conflict, .transient, .other:
            return String(localized: "iCloud could not do that right now. Try again in a moment.")
        }
    }
}

/// Waiting times between attempts: doubles each time, capped, with a longer start for full storage.
struct BackoffPolicy: Equatable, Sendable {
    var base: TimeInterval = 15
    var cap: TimeInterval = 15 * 60
    var quotaBase: TimeInterval = 10 * 60
    var quotaCap: TimeInterval = 6 * 60 * 60

    /// `attempt` starts at 0 for the first failure.
    func delay(afterFailures attempt: Int, for failure: SyncFailure) -> TimeInterval {
        let start: TimeInterval
        let limit: TimeInterval
        if case .quotaExceeded = failure {
            start = quotaBase
            limit = quotaCap
        } else {
            start = base
            limit = cap
        }
        let steps = min(max(attempt, 0), 20)
        let computed = min(start * pow(2, Double(steps)), limit)
        return max(computed, failure.retryAfter ?? 0)
    }
}
