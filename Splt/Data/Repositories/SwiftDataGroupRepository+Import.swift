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

            try SwiftDataExpenseRepository(env).insertBatch(
                parsed.expenses, createdBy: try env.currentUser()?.personID
            )
            try SwiftDataPaymentRepository(env).insertBatch(parsed.payments)
            try env.log(
                .expensesImported(expenses: parsed.expenses.count, payments: parsed.payments.count), groupID: group
            )
            try env.save()
            return ImportSummary(
                expensesAdded: parsed.expenses.count, paymentsAdded: parsed.payments.count,
                peopleAdded: added, warnings: parsed.warnings
            )
        } catch {
            env.tracker.rollback()
            throw error
        }
    }
}
