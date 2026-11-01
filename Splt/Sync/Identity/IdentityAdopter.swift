import Foundation
import SpltCore
import SwiftData

enum IdentityAdoption: Equatable, Sendable {
    /// There is no profile on this device yet, so there is nothing to change.
    case noProfile
    case alreadyUsing(PersonID)
    case adopted(PersonID)
    /// The old and new identity share a record, so the profile was left as it is.
    case blocked(records: Int)
}

/// Makes the profile of this device use the id derived from the iCloud user, so every device of
/// one person is the same person in every group.
@MainActor
struct IdentityAdopter {
    let tracker: ChangeTracker

    @discardableResult
    func adopt(userRecordName: String) throws -> IdentityAdoption {
        let target = CloudIdentity.personID(forUserRecordName: userRecordName)
        let context = tracker.context
        let me = PersonKind.me.rawValue
        var descriptor = FetchDescriptor<PersonRecord>(
            predicate: #Predicate { $0.kindRaw == me && $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        guard let current = try context.fetch(descriptor).first else { return .noProfile }
        if current.id == target.rawValue { return .alreadyUsing(target) }

        switch try ReferenceRewriter(tracker: tracker).rewrite(from: current.id, to: target.rawValue) {
        case .blocked(let records):
            return .blocked(records: records)
        case .rewritten:
            break
        }

        if let existing = try PersonRecord.find(recordName: target.description, in: context) {
            existing.kind = .me
            existing.claimedByCloudUserID = userRecordName
            if existing.deletedAt != nil {
                tracker.restore(existing)
            } else {
                tracker.recordEdit(existing)
            }
        } else {
            let profile = PersonRecord(
                id: target.rawValue, name: current.name, contactHint: current.contactHint, kind: .me,
                claimedByCloudUserID: userRecordName, avatarSeed: current.avatarSeed, createdAt: current.createdAt
            )
            context.insert(profile)
            tracker.recordEdit(profile)
        }
        current.kind = .friend
        tracker.tombstone(current)
        try tracker.save()
        return .adopted(target)
    }
}
