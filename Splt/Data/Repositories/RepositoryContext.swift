import Foundation
import SpltCore
import SwiftData

/// What the SwiftData repositories share: the context, the change tracker and a clock.
@MainActor
final class RepositoryContext {
    let context: ModelContext
    let tracker: ChangeTracker
    let now: @Sendable () -> Date
    /// A context does not keep its container alive, so anything that uses this object holds the container too.
    private let container: ModelContainer?

    init(context: ModelContext, container: ModelContainer? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.context = context
        self.container = container
        self.now = now
        self.tracker = ChangeTracker(context: context, now: now)
    }

    convenience init(container: ModelContainer, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(context: container.mainContext, container: container, now: now)
    }

    func save() throws {
        try tracker.save()
    }

    func personRecord(_ id: PersonID) throws -> PersonRecord? {
        guard let record = try PersonRecord.find(recordName: id.description, in: context), record.deletedAt == nil else {
            return nil
        }
        return record
    }

    func groupRecord(_ id: GroupID) throws -> GroupRecord? {
        guard let record = try GroupRecord.find(recordName: id.description, in: context), record.deletedAt == nil else {
            return nil
        }
        return record
    }

    func expenseRecord(_ id: ExpenseID) throws -> ExpenseRecord? {
        try ExpenseRecord.find(recordName: id.description, in: context)
    }

    func paymentRecord(_ id: PaymentID) throws -> PaymentRecord? {
        try PaymentRecord.find(recordName: id.description, in: context)
    }

    func currentUser() throws -> PersonRecord? {
        let me = PersonKind.me.rawValue
        var descriptor = FetchDescriptor<PersonRecord>(
            predicate: #Predicate { $0.kindRaw == me && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func expenses(inGroup groupID: GroupID, includeDeleted: Bool = false) throws -> [Expense] {
        let gid: UUID? = groupID.rawValue
        let descriptor = FetchDescriptor<ExpenseRecord>(
            predicate: includeDeleted
                ? #Predicate { $0.groupID == gid }
                : #Predicate { $0.groupID == gid && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).compactMap { try? Expense($0) }
    }

    func payments(inGroup groupID: GroupID, includeDeleted: Bool = false) throws -> [Payment] {
        let gid: UUID? = groupID.rawValue
        let descriptor = FetchDescriptor<PaymentRecord>(
            predicate: includeDeleted
                ? #Predicate { $0.groupID == gid }
                : #Predicate { $0.groupID == gid && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(Payment.init)
    }

    func ledger(forGroup groupID: GroupID) throws -> Ledger {
        Ledger(expenses: try expenses(inGroup: groupID), payments: try payments(inGroup: groupID))
    }

    func allGroups(includeArchived: Bool = true) throws -> [SplitGroup] {
        let descriptor = FetchDescriptor<GroupRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(SplitGroup.init).filter { includeArchived || !$0.isArchived }
    }

    /// Writes an activity row for the current user. Does nothing if there is no group to attach it to.
    func log(_ event: ActivityEvent, groupID: GroupID?) throws {
        let entry = ActivityEntry(
            groupID: groupID, actorID: try currentUser()?.personID, event: event, createdAt: now()
        )
        let record = ActivityRecord(entry)
        context.insert(record)
        tracker.recordEdit(record)
    }
}
