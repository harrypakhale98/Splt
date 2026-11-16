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
        guard let current = try context.fetch(descriptor).first else {
            // your own person, synced from another device, arrives as a friend
            guard let mine = try PersonRecord.find(recordName: target.description, in: context), mine.deletedAt == nil else {
                return .noProfile
            }
            mine.kind = .me
            try tracker.save()
            return .adopted(target)
        }
        if current.id == target.rawValue { return .alreadyUsing(target) }
        if let owner = current.claimedByCloudUserID, owner != userRecordName {
            return try takeOver(from: current, as: target, userRecordName: userRecordName)
        }

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

    /// The profile belongs to another iCloud account, whose groups stay on this device as local copies.
    /// It stays that person in them: rewriting it would put the other account's name and history under
    /// this one. The new account's own profile comes from its groups, so the one made here is only a
    /// stand in that any copy from the server replaces, and is never uploaded while it is called "You".
    private func takeOver(from previous: PersonRecord, as target: PersonID, userRecordName: String) throws -> IdentityAdoption {
        let context = tracker.context
        previous.kind = .friend
        if let existing = try PersonRecord.find(recordName: target.description, in: context) {
            existing.kind = .me
            existing.claimedByCloudUserID = userRecordName
            if existing.deletedAt != nil {
                existing.deletedAt = nil
                existing.modifiedAt = .distantStandIn
            }
        } else {
            let profile = PersonRecord(
                id: target.rawValue, name: String(localized: "You"), kind: .me,
                claimedByCloudUserID: userRecordName, avatarSeed: Int.random(in: 0..<10_000), createdAt: tracker.now()
            )
            profile.modifiedAt = .distantStandIn
            context.insert(profile)
        }
        try tracker.save()
        return .adopted(target)
    }
}
