import Foundation
import SpltCore
import SwiftData

@MainActor
final class SwiftDataGroupRepository: GroupRepository {
    let env: RepositoryContext

    init(_ env: RepositoryContext) {
        self.env = env
    }

    func groups(includeArchived: Bool) throws -> [SplitGroup] {
        try env.allGroups(includeArchived: includeArchived)
    }

    func group(id: GroupID) throws -> SplitGroup? {
        try env.groupRecord(id).map(SplitGroup.init)
    }

    func create(_ group: SplitGroup) throws {
        var group = group
        group.name = group.name.limited(to: RecordLimits.name)
        let record = GroupRecord(group)
        env.context.insert(record)
        env.tracker.recordEdit(record)
        try env.log(.groupCreated(name: group.name), groupID: group.id)
        try env.save()
    }

    func update(_ group: SplitGroup) throws {
        var group = group
        group.name = group.name.limited(to: RecordLimits.name)
        guard let record = try env.groupRecord(group.id) else { throw DataError.notFound("group \(group.id)") }
        let previousName = record.name
        let members = record.memberIDs
        record.update(from: group)
        record.memberIDs = members
        env.tracker.recordEdit(record)
        if previousName != group.name {
            try env.log(.groupRenamed(from: previousName, to: group.name), groupID: group.id)
        }
        try env.save()
    }

    func setArchived(_ archived: Bool, id: GroupID) throws {
        guard let record = try env.groupRecord(id) else { throw DataError.notFound("group \(id)") }
        guard record.isArchived != archived else { return }
        record.isArchived = archived
        env.tracker.recordEdit(record)
        try env.log(archived ? .groupArchived : .groupRestored, groupID: id)
        try env.save()
    }

    func delete(id: GroupID) throws {
        guard let record = try env.groupRecord(id) else { return }
        let gid: UUID? = id.rawValue
        for expense in try env.context.fetch(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.groupID == gid })) {
            env.tracker.tombstone(expense)
        }
        for payment in try env.context.fetch(FetchDescriptor<PaymentRecord>(predicate: #Predicate { $0.groupID == gid })) {
            env.tracker.tombstone(payment)
        }
        for comment in try env.context.fetch(FetchDescriptor<CommentRecord>(predicate: #Predicate { $0.groupID == gid })) {
            env.tracker.tombstone(comment)
        }
        for activity in try env.context.fetch(FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.groupID == gid })) {
            env.tracker.tombstone(activity)
        }
        for template in try env.context.fetch(FetchDescriptor<RecurringExpenseRecord>(predicate: #Predicate { $0.groupID == gid })) {
            env.tracker.tombstone(template)
        }
        env.tracker.tombstone(record)
        try env.save()
    }

    func addMember(_ person: PersonID, to group: GroupID) throws {
        guard let record = try env.groupRecord(group) else { throw DataError.notFound("group \(group)") }
        guard !record.memberIDs.contains(person.rawValue) else { return }
        record.memberIDs.append(person.rawValue)
        env.tracker.recordEdit(record)
        try env.log(.memberAdded(person), groupID: group)
        try env.save()
    }

    func removeMember(_ person: PersonID, from group: GroupID) throws {
        guard let record = try env.groupRecord(group) else { throw DataError.notFound("group \(group)") }
        guard record.memberIDs.contains(person.rawValue) else { return }
        let ledger = try env.ledger(forGroup: group)
        guard ledger.balances(of: person).isEmpty else { throw DataError.memberStillHasBalance(person) }
        if let title = try recurringExpenseTitle(involving: person, in: group) {
            throw DataError.memberOnRecurringExpense(title)
        }
        record.memberIDs.removeAll { $0 == person.rawValue }
        env.tracker.recordEdit(record)
        try env.log(.memberRemoved(person), groupID: group)
        try env.save()
    }

    func recurringExpenseTitle(involving person: PersonID, in group: GroupID) throws -> String? {
        try SwiftDataRecurringExpenseRepository(env).templates(in: group).first { $0.willInvolve(person) }?.title
    }

    func balances(for group: GroupID) throws -> GroupBalances {
        guard let record = try env.groupRecord(group) else { throw DataError.notFound("group \(group)") }
        return GroupBalances(
            groupID: group, ledger: try env.ledger(forGroup: group), simplifiesDebts: record.simplifiesDebts
        )
    }

    func export(group: GroupID, format: ExportFormat) throws -> Data {
        guard let record = try env.groupRecord(group) else { throw DataError.notFound("group \(group)") }
        let value = SplitGroup(record)
        let expenses = try env.expenses(inGroup: group)
        let payments = try env.payments(inGroup: group)
        var ids = value.memberIDs
        for id in (expenses.flatMap(\.participants) + payments.flatMap { [$0.payer, $0.receiver] }).sorted()
        where !ids.contains(id) {
            ids.append(id)
        }
        let people = try SwiftDataPersonRepository(env).people(ids: ids)
        let snapshot = GroupExportSnapshot(
            group: value, people: people, expenses: expenses, payments: payments, exportedAt: env.now()
        )
        switch format {
        case .csv: return GroupCSVExporter.data(for: snapshot)
        case .json: return try GroupJSONExporter.data(for: snapshot)
        }
    }
}
