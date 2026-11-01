import Foundation
import SpltCore
import SwiftData

@MainActor
final class SwiftDataExpenseRepository: ExpenseRepository {
    private let env: RepositoryContext

    init(_ env: RepositoryContext) {
        self.env = env
    }

    func expenses(in group: GroupID, includeDeleted: Bool) throws -> [Expense] {
        try env.expenses(inGroup: group, includeDeleted: includeDeleted)
    }

    func sharedExpenses(with friend: PersonID) throws -> [Expense] {
        guard let me = try env.currentUser()?.personID else { return [] }
        let descriptor = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try env.context.fetch(descriptor).compactMap { try? Expense($0) }.filter {
            let participants = $0.participants
            return participants.contains(me) && participants.contains(friend)
        }
    }

    func expense(id: ExpenseID) throws -> Expense? {
        try env.expenseRecord(id).map(Expense.init)
    }

    func details(id: ExpenseID) throws -> ExpenseDetails? {
        try env.expenseRecord(id)?.details
    }

    func add(_ expense: Expense, extras: ExpenseExtras) throws {
        try insert(expense, extras: extras, logsActivity: true)
        try env.save()
    }

    /// Stores an expense without saving. Importers pass `logsActivity: false` and write one summary entry instead.
    func insert(_ expense: Expense, extras: ExpenseExtras, logsActivity: Bool) throws {
        guard let groupID = expense.groupID else { throw DataError.missingGroup }
        guard try env.groupRecord(groupID) != nil else { throw DataError.notFound("group \(groupID)") }
        try Self.validate(expense)
        guard try env.expenseRecord(expense.id) == nil else { throw DataError.alreadyExists("expense \(expense.id)") }
        let record = ExpenseRecord(
            expense, extras: extras, createdBy: try env.currentUser()?.personID, createdAt: env.now()
        )
        env.context.insert(record)
        env.tracker.recordEdit(record)
        if logsActivity {
            try env.log(.expenseAdded(Self.reference(expense)), groupID: groupID)
        }
    }

    func update(_ expense: Expense, extras: ExpenseExtras?) throws {
        guard let record = try env.expenseRecord(expense.id), record.deletedAt == nil else {
            throw DataError.notFound("expense \(expense.id)")
        }
        guard let groupID = expense.groupID else { throw DataError.missingGroup }
        try Self.validate(expense)
        let old = try Expense(record)
        let oldExtras = record.extras
        let newExtras = extras ?? oldExtras
        let changed = ExpenseDiff.changedFields(from: old, to: expense, oldExtras: oldExtras, newExtras: newExtras)
        guard !changed.isEmpty else { return }

        var history = record.history
        history.append(ExpenseEditEntry(
            date: env.now(),
            editor: try env.currentUser()?.personID,
            changedFields: changed,
            previousTitle: changed.contains(.title) ? old.title : nil,
            previousTotal: changed.contains(.total) ? old.total : nil
        ))
        record.update(from: expense)
        record.apply(newExtras)
        record.history = history
        env.tracker.recordEdit(record)
        try env.log(.expenseEdited(Self.reference(expense)), groupID: groupID)
        try env.save()
    }

    func delete(id: ExpenseID) throws {
        guard let record = try env.expenseRecord(id) else { throw DataError.notFound("expense \(id)") }
        guard record.deletedAt == nil else { return }
        let expense = try Expense(record)
        env.tracker.softDelete(record)
        try env.log(.expenseDeleted(Self.reference(expense)), groupID: expense.groupID)
        try env.save()
    }

    func restore(id: ExpenseID) throws {
        guard let record = try env.expenseRecord(id) else { throw DataError.notFound("expense \(id)") }
        guard record.deletedAt != nil else { return }
        env.tracker.restore(record)
        let expense = try Expense(record)
        try env.log(.expenseRestored(Self.reference(expense)), groupID: expense.groupID)
        try env.save()
    }

    func duplicates(of expense: Expense, withinDays days: Int) throws -> [Expense] {
        guard let groupID = expense.groupID else { return [] }
        let gid: UUID? = groupID.rawValue
        let units = expense.total.minorUnits
        let currency = expense.total.currencyCode
        let descriptor = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate {
                $0.groupID == gid && $0.deletedAt == nil && $0.totalMinorUnits == units && $0.currencyCode == currency
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let window = TimeInterval(max(days, 0)) * 86_400
        return try env.context.fetch(descriptor)
            .filter { $0.id != expense.id.rawValue }
            .filter { abs($0.date.timeIntervalSince(expense.date)) <= window }
            .filter { TitleSimilarity.areSimilar($0.title, expense.title) }
            .compactMap { try? Expense($0) }
    }

    private static func validate(_ expense: Expense) throws {
        do {
            try expense.validate()
        } catch let error as ExpenseError {
            throw DataError.invalidExpense(error)
        }
    }

    static func reference(_ expense: Expense) -> ExpenseReference {
        ExpenseReference(id: expense.id, title: expense.title, amount: expense.total)
    }
}
