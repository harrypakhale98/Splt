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

    func addAll(_ expenses: [Expense]) throws {
        guard !expenses.isEmpty else { return }
        do {
            let me = try env.currentUser()?.personID
            try insertBatch(expenses, createdBy: me)
            let counts = Dictionary(grouping: expenses.compactMap(\.groupID), by: { $0 }).mapValues(\.count)
            for group in counts.keys.sorted() {
                try env.log(.expensesImported(expenses: counts[group] ?? 0, payments: 0), groupID: group, actor: me)
            }
            try env.save()
        } catch {
            env.tracker.rollback()
            throw error
        }
    }

    /// Stores an expense without saving. Importers pass `logsActivity: false` and write one summary entry instead.
    func insert(_ expense: Expense, extras: ExpenseExtras, logsActivity: Bool) throws {
        guard let groupID = expense.groupID else { throw DataError.missingGroup }
        guard try env.groupRecord(groupID) != nil else { throw DataError.notFound("group \(groupID)") }
        try Self.validate(expense)
        guard try env.expenseRecord(expense.id) == nil else { throw DataError.alreadyExists("expense \(expense.id)") }
        let me = try env.currentUser()?.personID
        let record = ExpenseRecord(expense, extras: extras, createdBy: me, createdAt: env.now())
        env.context.insert(record)
        env.tracker.recordEdit(record)
        if logsActivity {
            try env.log(.expenseAdded(Self.reference(expense)), groupID: groupID, actor: me)
        }
    }

    /// Stores many expenses without saving or logging. Everything is checked first, with a handful
    /// of queries instead of one per expense, so a bad row leaves the store untouched.
    func insertBatch(_ expenses: [Expense], extras: ExpenseExtras = ExpenseExtras(), createdBy: PersonID?) throws {
        var knownGroups = Set<GroupID>()
        var seen = Set<ExpenseID>()
        for expense in expenses {
            guard let groupID = expense.groupID else { throw DataError.missingGroup }
            if knownGroups.insert(groupID).inserted, try env.groupRecord(groupID) == nil {
                throw DataError.notFound("group \(groupID)")
            }
            try Self.validate(expense)
            guard seen.insert(expense.id).inserted else { throw DataError.alreadyExists("expense \(expense.id)") }
        }
        let existing = try env.existingExpenseIDs(among: expenses.map(\.id.rawValue))
        if let clash = expenses.first(where: { existing.contains($0.id.rawValue) }) {
            throw DataError.alreadyExists("expense \(clash.id)")
        }
        let created = env.now()
        for expense in expenses {
            let record = ExpenseRecord(expense, extras: extras, createdBy: createdBy, createdAt: created)
            env.context.insert(record)
            env.tracker.recordEdit(record)
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

        env.tracker.noteBalanceChange(type: .expense, zone: record.zoneName)
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
