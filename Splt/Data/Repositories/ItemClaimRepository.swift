import Foundation
import SpltCore
import SwiftData

@MainActor
protocol ItemClaimRepository {
    /// The live claims on an expense, at most one per person.
    func claims(on expense: ExpenseID) throws -> [ItemClaim]
    /// Stores the items you had. Only your own claim is written, never the expense, so people
    /// picking at the same time cannot overwrite each other. On the device of the person who
    /// added the expense, the picks are folded into the split straight away.
    func setMyPicks(_ itemIDs: Set<UUID>, on expense: ExpenseID) throws
    /// Folds claims into the expenses you added, in the given groups or all of them.
    /// Expenses whose split would not change are left untouched. Returns how many changed.
    @discardableResult
    func foldClaims(inGroups groups: Set<GroupID>?) throws -> Int
}

@MainActor
final class SwiftDataItemClaimRepository: ItemClaimRepository {
    private let env: RepositoryContext
    private let expenses: any ExpenseRepository

    init(_ env: RepositoryContext, expenses: any ExpenseRepository) {
        self.env = env
        self.expenses = expenses
    }

    func claims(on expense: ExpenseID) throws -> [ItemClaim] {
        let id = expense.rawValue
        let descriptor = FetchDescriptor<ItemClaimRecord>(
            predicate: #Predicate { $0.expenseID == id && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try env.context.fetch(descriptor).map(ItemClaim.init).filter(\.hasItsOwnID)
    }

    func setMyPicks(_ itemIDs: Set<UUID>, on expenseID: ExpenseID) throws {
        guard let me = try env.currentUser()?.personID else { throw DataError.notFound("me") }
        guard let record = try env.expenseRecord(expenseID), record.deletedAt == nil else {
            throw DataError.notFound("expense \(expenseID)")
        }
        let id = ItemClaimRecord.claimID(expenseID: expenseID.rawValue, personID: me.rawValue)
        if let claim = try ItemClaimRecord.find(recordName: id.uuidString, in: env.context) {
            let unchanged = Set(claim.itemIDs) == itemIDs && claim.deletedAt == nil
            guard !unchanged else { return }
            claim.itemIDs = Array(itemIDs)
            if claim.deletedAt != nil {
                env.tracker.restore(claim)
            } else {
                env.tracker.recordEdit(claim)
            }
        } else {
            let claim = ItemClaimRecord(
                groupID: record.groupID, expenseID: expenseID.rawValue, personID: me.rawValue,
                itemIDs: Array(itemIDs), createdAt: env.now()
            )
            env.context.insert(claim)
            env.tracker.recordEdit(claim)
        }
        try env.save()
        if record.createdByID == me.rawValue {
            try fold(expenseID)
        }
    }

    func foldClaims(inGroups groups: Set<GroupID>?) throws -> Int {
        guard let me = try env.currentUser()?.id else { return 0 }
        let descriptor = FetchDescriptor<ItemClaimRecord>(predicate: #Predicate { $0.deletedAt == nil })
        var expenseIDs = Set<UUID>()
        for claim in try env.context.fetch(descriptor) {
            if let groups, !groups.contains(where: { $0.rawValue == claim.groupID }) { continue }
            expenseIDs.insert(claim.expenseID)
        }
        var changed = 0
        for id in expenseIDs.sorted() {
            guard let record = try env.expenseRecord(ExpenseID(rawValue: id)), record.createdByID == me else { continue }
            if try fold(ExpenseID(rawValue: id)) { changed += 1 }
        }
        return changed
    }

    /// Only the device of the person who added an expense calls this, so the expense has one editor.
    @discardableResult
    private func fold(_ id: ExpenseID) throws -> Bool {
        guard let expense = try expenses.expense(id: id),
              let updated = ItemClaimFold.folding(try claims(on: id), into: expense),
              (try? updated.validate()) != nil else { return false }
        try expenses.update(updated, extras: nil)
        return true
    }
}
