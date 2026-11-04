import Foundation
import SpltCore
import SwiftUI

/// What the group screens need from sharing. Sync supplies the real answers; this seam keeps the
/// screens working, and testable, when sync is not available.
protocol GroupSharing: Sendable {
    /// Tells sync this device is leaving the group. Local membership is changed by the caller.
    func leave(groupID: GroupID) async throws
    /// True when this person shared the group with others. Leaving is not possible then, because
    /// the group lives in their iCloud and CloudKit cannot hand it to someone else.
    func isSharedByMe(groupID: GroupID) async -> Bool
}

/// Used until sync provides sharing: nothing is shared, so there is nothing to tell.
struct LocalGroupSharing: GroupSharing {
    func leave(groupID: GroupID) async throws {}

    func isSharedByMe(groupID: GroupID) async -> Bool { false }
}

extension EnvironmentValues {
    @Entry var groupSharing: any GroupSharing = LocalGroupSharing()
}
