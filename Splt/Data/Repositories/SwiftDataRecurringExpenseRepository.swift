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
        let template = Self.fitted(template)
        guard let groupID = template.groupID else { throw DataError.missingGroup }
        guard try env.groupRecord(groupID) != nil else { throw DataError.notFound("group \(groupID)") }
        let record = RecurringExpenseRecord(template)
        env.context.insert(record)
        env.tracker.recordEdit(record)
        try env.save()
    }

    func update(_ template: RecurringExpense) throws {
        let template = Self.fitted(template)
        guard let record = try RecurringExpenseRecord.find(recordName: template.id.uuidString, in: env.context),
              record.deletedAt == nil else { throw DataError.notFound("recurring expense \(template.id)") }
        let resumed = !record.isActive && template.isActive
        record.update(from: template)
        // Occurrences missed while paused are not billed: the schedule picks up after this moment.
        if resumed { record.lastCreatedOccurrence = max(record.lastCreatedOccurrence ?? .distantPast, env.now()) }
        env.tracker.recordEdit(record)
        try env.save()
    }

    func delete(id: UUID) throws {
        guard let record = try RecurringExpenseRecord.find(recordName: id.uuidString, in: env.context),
              record.deletedAt == nil else { return }
        env.tracker.tombstone(record)
        try env.save()
    }

    private static func fitted(_ template: RecurringExpense) -> RecurringExpense {
        var template = template
        template.title = template.title.limited(to: RecordLimits.name)
        template.note = template.note.limited(to: RecordLimits.text)
        return template
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
                  let group = try env.groupRecord(groupID) else { continue }
            // An archived group is put away. What came due meanwhile is caught up when it is restored.
            if group.isArchived { continue }
            // Anyone in a group can sync a template that started decades ago, and every member's device makes
            // its expenses. Older occurrences are not billed, and a backlog goes a little on each run.
            let oldest = now.addingTimeInterval(-366 * 86_400)
            let due = template.rule.dueOccurrences(
                after: max(template.lastCreatedOccurrence ?? .distantPast, oldest), through: now, limit: 100
            )
            guard let latest = due.last else { continue }
            // a template that cannot make a valid expense must not stop the others
            guard (try? template.expense(on: latest).validate()) != nil else { continue }
            for occurrence in due {
                var expense = template.expense(on: occurrence)
                expense.id = OccurrenceID.expenseID(template: template.id, occurrence: occurrence)
                if try env.expenseRecord(expense.id) == nil {
                    try expenses.insert(expense, extras: ExpenseExtras(recurringExpenseID: template.id), logsActivity: false)
                    try env.log(
                        .expenseAdded(SwiftDataExpenseRepository.reference(expense)), groupID: groupID,
                        actor: try env.currentUser()?.personID, id: OccurrenceID.addedEntryID(expense: expense.id),
                        isNews: true
                    )
                    // This can run before the first fetch, so another device may have made this occurrence
                    // and since edited or deleted it. Dated by its occurrence, this copy loses to any such change.
                    try env.expenseRecord(expense.id)?.modifiedAt = occurrence
                    created.append(expense)
                }
            }
            // the date comes back from CloudKit cut to milliseconds, which is not a new occurrence
            if record.lastCreatedOccurrence.map({ latest.isLaterEdit(than: $0) }) ?? true {
                record.lastCreatedOccurrence = latest
                env.tracker.recordBookkeeping(record)
            }
            try env.save()
        }
        return created
    }
}
