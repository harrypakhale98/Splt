import Foundation
import SpltCore
import SwiftData

extension SwiftDataGroupRepository {
    func importSplitwiseCSV(_ text: String, into group: GroupID) throws -> ImportSummary {
        guard let record = try env.groupRecord(group) else { throw DataError.notFound("group \(group)") }
        let existing = try SwiftDataPersonRepository(env).people(ids: SplitGroup(record).memberIDs)
        var known: [String: PersonID] = [:]
        for person in existing { known[person.name] = person.id }
        let parsed = try SplitwiseCSVImporter.parse(text, groupID: group, knownPeople: known)

        do {
            let existingIDs = Set(existing.map(\.id))
            var added = 0
            for name in parsed.memberNames {
                guard let id = parsed.members[name], !existingIDs.contains(id) else { continue }
                let person = PersonRecord(Person(id: id, name: name, kind: .placeholder, createdAt: env.now()))
                env.context.insert(person)
                env.tracker.recordEdit(person)
                record.memberIDs.append(id.rawValue)
                added += 1
            }
            env.tracker.recordEdit(record)

            let expenses = SwiftDataExpenseRepository(env)
            for expense in parsed.expenses {
                try expenses.insert(expense, extras: ExpenseExtras(), logsActivity: false)
            }
            let payments = SwiftDataPaymentRepository(env)
            for payment in parsed.payments {
                try payments.insert(payment, logsActivity: false)
            }
            try env.log(
                .expensesImported(expenses: parsed.expenses.count, payments: parsed.payments.count), groupID: group
            )
            try env.save()
            return ImportSummary(
                expensesAdded: parsed.expenses.count, paymentsAdded: parsed.payments.count,
                peopleAdded: added, warnings: parsed.warnings
            )
        } catch {
            env.context.rollback()
            throw error
        }
    }
}
