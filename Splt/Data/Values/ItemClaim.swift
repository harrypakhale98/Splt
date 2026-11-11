import Foundation
import SpltCore

/// The items of an expense split by item that one person says they had.
struct ItemClaim: Hashable, Sendable, Identifiable {
    var id: UUID
    var groupID: GroupID?
    var expenseID: ExpenseID
    var personID: PersonID
    var itemIDs: Set<UUID>
    var modifiedAt: Date
}

extension ItemClaim {
    init(_ record: ItemClaimRecord) {
        self.init(
            id: record.id,
            groupID: record.groupID.map { GroupID(rawValue: $0) },
            expenseID: ExpenseID(rawValue: record.expenseID),
            personID: PersonID(rawValue: record.personID),
            itemIDs: Set(record.itemIDs),
            modifiedAt: record.modifiedAt
        )
    }

    /// Whether this is the one claim the person can have on the expense. Sync only accepts that
    /// one, but a record written some other way could carry any id.
    var hasItsOwnID: Bool {
        id == ItemClaimRecord.claimID(expenseID: expenseID.rawValue, personID: personID.rawValue)
    }
}

/// Folds people's claims into an expense split by item.
///
/// A claim is applied only when it is newer than the expense's last edit, so whoever acted last
/// wins: a change the person who added the expense makes after a claim stays, and a claim made
/// after that change is applied. After a fold the expense is newer than every claim, so running
/// it again changes nothing.
///
/// An applied claim adds the claimant to the items they picked and takes them off the other items
/// anyone picked. Items nobody picked keep their people, and nobody is taken off an item they are
/// the last one on, so every item keeps someone to pay for it. A claim does not count when it is
/// deleted, when its person is not in the expense, or when none of its items still exist. Tax, tip
/// and discount are left alone and spread by `SplitCalculator` as before.
enum ItemClaimFold {
    /// Claims newer than `since` are applied. Older ones only mark which items were picked.
    static func folded(
        _ split: ItemizedSplit, people: Set<PersonID>, claims: [ItemClaim], since: Date = .distantPast
    ) -> ItemizedSplit {
        let existing = Set(split.items.map(\.id))
        var picked = Set<UUID>()
        var applied: [PersonID: Set<UUID>] = [:]
        for claim in claims where claim.hasItsOwnID && people.contains(claim.personID) {
            let items = claim.itemIDs.intersection(existing)
            guard !items.isEmpty else { continue }
            picked.formUnion(items)
            if claim.modifiedAt.isLaterEdit(than: since) {
                applied[claim.personID, default: []].formUnion(items)
            }
        }
        var result = split
        for index in result.items.indices where picked.contains(result.items[index].id) {
            let item = result.items[index].id
            let claimants = applied.sorted(by: { $0.key < $1.key })
            // everyone who picked the item goes on first, so taking people off can never depend on
            // the order the claimants come in
            for (person, items) in claimants where items.contains(item) {
                result.items[index].assignees.insert(person)
            }
            for (person, items) in claimants where !items.contains(item) {
                if result.items[index].assignees != [person] {
                    result.items[index].assignees.remove(person)
                }
            }
        }
        return result
    }

    /// The expense with the claims newer than its last edit folded in, or nil when it is not split
    /// by item or nothing changes.
    static func folding(_ claims: [ItemClaim], into expense: Expense, modifiedAt: Date) -> Expense? {
        guard case .itemized(let split) = expense.split, !expense.isDeleted else { return nil }
        let claims = claims.filter { $0.expenseID == expense.id }
        let result = folded(split, people: expense.participants, claims: claims, since: modifiedAt)
        guard result != split else { return nil }
        var updated = expense
        updated.split = .itemized(result)
        return updated
    }
}
