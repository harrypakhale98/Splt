import Foundation
import SpltCore
import SwiftData

enum ClaimError: Error, Equatable {
    case notAPlaceholder
    case unknownPerson
    /// Both people appear in the same expense or payment, so their shares cannot be merged automatically.
    case bothInSameRecord(Int)
}

/// Lets a real participant take over a placeholder, for example "Sam" added by name before Sam joined.
/// Every reference to the placeholder is rewritten to the participant and the placeholder is deleted.
@MainActor
struct PlaceholderClaimer {
    let tracker: ChangeTracker

    /// Returns how many records now point at the participant.
    @discardableResult
    func claim(placeholder: PersonID, by participant: PersonID) throws -> Int {
        let context = tracker.context
        guard let old = try PersonRecord.find(recordName: placeholder.description, in: context), old.deletedAt == nil else {
            throw ClaimError.unknownPerson
        }
        guard old.kind == .placeholder else { throw ClaimError.notAPlaceholder }
        guard let new = try PersonRecord.find(recordName: participant.description, in: context), new.deletedAt == nil else {
            throw ClaimError.unknownPerson
        }
        switch try ReferenceRewriter(tracker: tracker).rewrite(from: placeholder.rawValue, to: participant.rawValue) {
        case .blocked(let records):
            throw ClaimError.bothInSameRecord(records)
        case .rewritten(let count):
            tracker.tombstone(old)
            if new.contactHint == nil, let hint = old.contactHint {
                new.contactHint = hint
                tracker.recordEdit(new)
            }
            try tracker.save()
            return count
        }
    }
}
