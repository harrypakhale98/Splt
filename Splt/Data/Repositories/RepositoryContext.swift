import Foundation
import SpltCore
import SwiftData

/// What the SwiftData repositories share: the context, the change tracker and a clock.
@MainActor
final class RepositoryContext {
    let context: ModelContext
    let tracker: ChangeTracker
    let now: @Sendable () -> Date
    /// Ledgers per group. The tracker keeps it current, so reads can trust it.
    let balanceCache: BalanceCache
    /// A context does not keep its container alive, so anything that uses this object holds the container too.
    private let container: ModelContainer?

    init(
        context: ModelContext,
        container: ModelContainer? = nil,
        balanceCache: BalanceCache = BalanceCache(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = context
        self.container = container
        self.now = now
        self.balanceCache = balanceCache
        self.tracker = ChangeTracker(context: context, balanceCache: balanceCache, now: now)
    }

    convenience init(
        container: ModelContainer, balanceCache: BalanceCache = BalanceCache(), now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(context: container.mainContext, container: container, balanceCache: balanceCache, now: now)
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

    /// The group's ledger, from the cache when nothing in the group changed since it was built.
    func ledger(forGroup groupID: GroupID) throws -> Ledger {
        try balanceCache.ledger(for: groupID) { try freshLedger(forGroup: groupID) }
    }

    /// Builds the ledger from the stored rows, ignoring the cache.
    func freshLedger(forGroup groupID: GroupID) throws -> Ledger {
        Ledger(expenses: try expenses(inGroup: groupID), payments: try payments(inGroup: groupID))
    }

    func allGroups(includeArchived: Bool = true) throws -> [SplitGroup] {
        let descriptor = FetchDescriptor<GroupRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(SplitGroup.init).filter { includeArchived || !$0.isArchived }
    }

    /// Ids from `ids` that already have an expense row, in a few queries rather than one per id.
    func existingExpenseIDs(among ids: [UUID]) throws -> Set<UUID> {
        var found = Set<UUID>()
        for chunk in Self.chunks(of: ids) {
            var descriptor = FetchDescriptor<ExpenseRecord>(predicate: #Predicate { chunk.contains($0.id) })
            descriptor.propertiesToFetch = [\.id]
            found.formUnion(try context.fetch(descriptor).map(\.id))
        }
        return found
    }

    func existingPaymentIDs(among ids: [UUID]) throws -> Set<UUID> {
        var found = Set<UUID>()
        for chunk in Self.chunks(of: ids) {
            var descriptor = FetchDescriptor<PaymentRecord>(predicate: #Predicate { chunk.contains($0.id) })
            descriptor.propertiesToFetch = [\.id]
            found.formUnion(try context.fetch(descriptor).map(\.id))
        }
        return found
    }

    private static func chunks(of ids: [UUID], size: Int = 400) -> [[UUID]] {
        stride(from: 0, to: ids.count, by: size).map { Array(ids[$0..<min($0 + size, ids.count)]) }
    }

    /// Writes an activity row for the current user.
    func log(_ event: ActivityEvent, groupID: GroupID?) throws {
        try log(event, groupID: groupID, actor: try currentUser()?.personID)
    }

    /// Writes an activity row for a known actor, which saves looking the current user up again.
    func log(_ event: ActivityEvent, groupID: GroupID?, actor: PersonID?, id: UUID = UUID()) throws {
        let entry = ActivityEntry(id: id, groupID: groupID, actorID: actor, event: event, createdAt: now())
        let record = ActivityRecord(entry)
        context.insert(record)
        tracker.recordEdit(record)
    }
}
