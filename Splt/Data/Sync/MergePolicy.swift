import Foundation

/// The version facts of one copy of a record that decide which copy wins.
struct SyncStamp: Hashable, Sendable {
    var modifiedAt: Date
    var deletedAt: Date?
    /// Any stable text that is the same on every device for the same content.
    var tieBreaker: String

    init(modifiedAt: Date, deletedAt: Date? = nil, tieBreaker: String = "") {
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.tieBreaker = tieBreaker
    }

    var isDeleted: Bool { deletedAt != nil }
}

enum MergeWinner: Hashable, Sendable {
    case local
    case remote
}

/// Decides which copy of a record survives when a device and the server disagree.
///
/// Every device must reach the same answer for the same pair of copies, so the rules use
/// only the stamps and never the order in which changes arrived.
///
/// 1. When neither copy is deleted, the later modification wins.
/// 2. A tombstone beats a live copy that was last edited at or before the delete.
///    A live copy edited after the delete wins, which is how an undo survives.
/// 3. When both copies are deleted, the later modification wins.
/// 4. Equal timestamps fall back to comparing the tie breaker text.
enum MergePolicy {
    static func winner(local: SyncStamp, remote: SyncStamp) -> MergeWinner {
        switch (local.deletedAt, remote.deletedAt) {
        case (nil, nil), (.some, .some):
            return latest(local: local, remote: remote)
        case (.some(let deletedAt), nil):
            return remote.modifiedAt > deletedAt ? .remote : .local
        case (nil, .some(let deletedAt)):
            return local.modifiedAt > deletedAt ? .local : .remote
        }
    }

    private static func latest(local: SyncStamp, remote: SyncStamp) -> MergeWinner {
        if local.modifiedAt != remote.modifiedAt {
            return local.modifiedAt > remote.modifiedAt ? .local : .remote
        }
        return local.tieBreaker >= remote.tieBreaker ? .local : .remote
    }
}

extension Date {
    /// True when this modified date comes from an edit after `sent`, the date a server handed back.
    /// CloudKit keeps whole milliseconds and may cut a date down to the one before, so anything closer
    /// than the two millisecond step between local edits is the same edit.
    func isLaterEdit(than sent: Date) -> Bool {
        timeIntervalSince(sent) > 0.0015
    }
}
