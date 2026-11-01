import Foundation
import SpltCore
import SwiftData

@MainActor
final class SwiftDataRecurringExpenseRepository: RecurringExpenseRepository {
    private let env: RepositoryContext

    init(_ env: RepositoryContext) {
        self.env = env
    }

    func templates(in group: GroupID) throws -> [RecurringExpense] {
        let gid: UUID? = group.rawValue
        let descriptor = FetchDescriptor<RecurringExpenseRecord>(
            predicate: #Predicate { $0.groupID == gid && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try env.context.fetch(descriptor).compactMap { try? RecurringExpense($0) }
    }

    func add(_ template: RecurringExpense) throws {
        guard let groupID = template.groupID else { throw DataError.missingGroup }
        guard try env.groupRecord(groupID) != nil else { throw DataError.notFound("group \(groupID)") }
        let record = RecurringExpenseRecord(template)
        env.context.insert(record)
        env.tracker.recordEdit(record)
        try env.save()
    }

    func update(_ template: RecurringExpense) throws {
        guard let record = try RecurringExpenseRecord.find(recordName: template.id.uuidString, in: env.context),
              record.deletedAt == nil else { throw DataError.notFound("recurring expense \(template.id)") }
        record.update(from: template)
        env.tracker.recordEdit(record)
        try env.save()
    }

    func delete(id: UUID) throws {
        guard let record = try RecurringExpenseRecord.find(recordName: id.uuidString, in: env.context),
              record.deletedAt == nil else { return }
        env.tracker.tombstone(record)
        try env.save()
    }

    @discardableResult
    func createDueExpenses(through now: Date) throws -> [Expense] {
        let descriptor = FetchDescriptor<RecurringExpenseRecord>(
            predicate: #Predicate { $0.isActive == true && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        var created: [Expense] = []
        let expenses = SwiftDataExpenseRepository(env)
        for record in try env.context.fetch(descriptor) {
            guard let template = try? RecurringExpense(record),
                  let groupID = template.groupID,
                  try env.groupRecord(groupID) != nil else { continue }
            let due = template.rule.dueOccurrences(after: template.lastCreatedOccurrence, through: now)
            guard let latest = due.last else { continue }
            for occurrence in due {
                var expense = template.expense(on: occurrence)
                expense.id = OccurrenceID.expenseID(template: template.id, occurrence: occurrence)
                if try env.expenseRecord(expense.id) == nil {
                    try expenses.add(expense, extras: ExpenseExtras(recurringExpenseID: template.id))
                    created.append(expense)
                }
            }
            record.lastCreatedOccurrence = latest
            env.tracker.recordEdit(record)
            try env.save()
        }
        return created
    }
}
