import Foundation

/// What sync is doing, in terms Settings can show to a person.
enum SyncStatus: Hashable, Sendable {
    case idle
    case syncing
    case offline
    case noAccount
    case restricted
    /// A problem that needs attention. The text is already friendly.
    case error(String)
    /// Sync isn't running, for a reason the person can't fix from their iCloud account.
    case unavailable(UnavailableReason)

    /// Why sync isn't running, so Settings can say something specific.
    enum UnavailableReason: Hashable, Sendable {
        /// The first moments after launch, before the iCloud account has been checked.
        case starting
        /// The Simulator, where CloudKit's pushes and sharing don't work.
        case simulator
        /// Tests and Xcode previews.
        case developerBuild
        /// A build signed without the iCloud capability.
        case notSetUp
    }

    var title: String {
        switch self {
        case .idle: String(localized: "Up to Date")
        case .syncing: String(localized: "Syncing")
        case .offline: String(localized: "Offline")
        case .noAccount: String(localized: "No iCloud Account")
        case .restricted: String(localized: "Restricted")
        case .error: String(localized: "Needs Attention")
        case .unavailable(.starting): String(localized: "Checking")
        case .unavailable(.simulator): String(localized: "Off in Simulator")
        case .unavailable(.developerBuild), .unavailable(.notSetUp): String(localized: "Off")
        }
    }

    var detail: String {
        switch self {
        case .idle:
            String(localized: "Your groups are in sync across your devices and the people you share with.")
        case .syncing:
            String(localized: "Sending and receiving changes.")
        case .offline:
            String(localized: "Changes are saved on this device and will sync when you are back online.")
        case .noAccount:
            String(localized: "Sign in to iCloud in the Settings app to share groups with friends.")
        case .restricted:
            String(localized: "iCloud is restricted on this device, so groups stay on this device.")
        case .error(let message):
            message
        case .unavailable(.starting):
            String(localized: "Checking your iCloud account.")
        case .unavailable(.simulator):
            String(localized: "Sync runs on iPhone. In the Simulator, your groups stay on this device.")
        case .unavailable(.developerBuild):
            String(localized: "Sync is off while testing. Your groups stay on this device.")
        case .unavailable(.notSetUp):
            String(localized: "This copy was built without iCloud, so your groups stay on this device.")
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "checkmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .offline: "icloud.slash"
        case .noAccount: "person.crop.circle.badge.exclamationmark"
        case .restricted: "lock.icloud"
        case .error: "exclamationmark.icloud"
        case .unavailable(.starting): "icloud"
        case .unavailable: "icloud.slash"
        }
    }

    /// True when changes can reach other devices right now or soon.
    var isConnected: Bool {
        switch self {
        case .idle, .syncing: true
        case .offline, .noAccount, .restricted, .error, .unavailable: false
        }
    }
}
