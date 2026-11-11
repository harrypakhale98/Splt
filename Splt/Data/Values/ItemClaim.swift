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
/// Each counted claim adds the claimant to the items they picked and takes them off the other
/// items someone picked. Items nobody picked keep their people, so no item is ever left without
/// someone to pay for it. A claim does not count when it is deleted, when its person is not in
/// the expense, or when none of its items still exist. Tax, tip and discount are left alone and
/// spread by `SplitCalculator` as before.
enum ItemClaimFold {
    static func folded(_ split: ItemizedSplit, people: Set<PersonID>, claims: [ItemClaim]) -> ItemizedSplit {
        let existing = Set(split.items.map(\.id))
        var picks: [PersonID: Set<UUID>] = [:]
        for claim in claims where claim.hasItsOwnID && people.contains(claim.personID) {
            let items = claim.itemIDs.intersection(existing)
            guard !items.isEmpty else { continue }
            picks[claim.personID, default: []].formUnion(items)
        }
        let picked = picks.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        var result = split
        for index in result.items.indices where picked.contains(result.items[index].id) {
            let item = result.items[index].id
            for (person, items) in picks {
                if items.contains(item) {
                    result.items[index].assignees.insert(person)
                } else {
                    result.items[index].assignees.remove(person)
                }
            }
        }
        return result
    }

    /// The expense with the claims folded in, or nil when it is not split by item or nothing changes.
    static func folding(_ claims: [ItemClaim], into expense: Expense) -> Expense? {
        guard case .itemized(let split) = expense.split, !expense.isDeleted else { return nil }
        let claims = claims.filter { $0.expenseID == expense.id }
        let result = folded(split, people: expense.participants, claims: claims)
        guard result != split else { return nil }
        var updated = expense
        updated.split = .itemized(result)
        return updated
    }
}
