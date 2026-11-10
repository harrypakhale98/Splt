import Foundation
import SpltCore
import SwiftUI

/// What the group screens need from sharing. Sync supplies the real link and answers; this seam
/// keeps the screens working, and testable, when sync is not available.
protocol GroupSharing: Sendable {
    /// A link that opens the group for whoever receives it.
    func inviteURL(for groupID: GroupID, groupName: String) async throws -> URL
    /// Tells sync this device is leaving the group. Local membership is changed by the caller.
    func leave(groupID: GroupID) async throws
    /// True when this person shared the group with others. Leaving is not possible then, because
    /// the group lives in their iCloud and CloudKit cannot hand it to someone else.
    func isSharedByMe(groupID: GroupID) async -> Bool
}

/// Used until sync provides sharing: the link is the app's own address for the group, which only
/// opens it on a device that already has the group, and nothing is shared.
struct LocalGroupSharing: GroupSharing {
    func inviteURL(for groupID: GroupID, groupName: String) async throws -> URL {
        DeepLink.group(groupID.rawValue).url
    }

    func leave(groupID: GroupID) async throws {}

    func isSharedByMe(groupID: GroupID) async -> Bool { false }
}

extension EnvironmentValues {
    @Entry var groupSharing: any GroupSharing = LocalGroupSharing()
}
