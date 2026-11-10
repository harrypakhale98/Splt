import Foundation
import SpltCore
import SwiftData

enum RewriteResult: Equatable, Sendable {
    /// The number of records that were rewritten and marked for upload.
    case rewritten(Int)
    /// Both ids appear in the same record, so merging them would need to combine amounts. Nothing was changed.
    /// Only records that can still be seen count: not deleted ones, and not those of a deleted group.
    case blocked(records: Int)
}

/// Replaces one person id with another in every record that mentions it. It works on the stored
/// text of each field, so it needs no knowledge of how splits, events or reactions are encoded.
@MainActor
struct ReferenceRewriter {
    let tracker: ChangeTracker

    /// Records whose amounts are keyed by person: two ids in one of them would have to be added together.
    private static let blocksMerge: Set<SyncRecordType> = [.expense, .payment, .recurringExpense]

    @discardableResult
    func rewrite(from old: UUID, to new: UUID) throws -> RewriteResult {
        let oldText = old.uuidString
        let newText = new.uuidString
        var changes: [(record: any SyncTracked, fields: SyncFields)] = []
        var blocked = 0

        for record in try tracker.allNonPersonRecords() {
            let fields = record.syncFields
            guard fields.referencedUUIDs.contains(oldText) else { continue }
            let bothPresent = fields.referencedUUIDs.contains(newText)
            let isGroup = record.recordType == .group
            if bothPresent && Self.blocksMerge.contains(record.recordType) {
                // A deleted record cannot be edited out of the way, so it must not block.
                if try record.deletedAt == nil && !isInDeletedGroup(record) {
                    blocked += 1
                } else if let combined = combined(record, fields, old: old, new: new) {
                    changes.append((record, replaced(combined, old: oldText, new: newText, mergeMembers: false)))
                }
                continue
            }
            changes.append((record, replaced(fields, old: oldText, new: newText, mergeMembers: isGroup)))
        }
        guard blocked == 0 else { return .blocked(records: blocked) }

        for change in changes {
            change.record.applySyncFields(change.fields)
            if change.record.deletedAt != nil && change.record.pendingOperation == .delete { continue }
            // a deleted or left group is history on this device: uploading it would bring its zone back
            if try isInDeletedGroup(change.record) { continue }
            tracker.recordEdit(change.record)
        }
        try tracker.save()
        return .rewritten(changes.count)
    }

    private func isInDeletedGroup(_ record: any SyncTracked) throws -> Bool {
        guard let zone = record.zoneName else { return false }
        return try GroupRecord.find(recordName: zone, in: tracker.context)?.deletedAt != nil
    }

    /// The fields of a deleted record that names both people, with their amounts added together,
    /// or nil to leave the record as it is.
    ///
    /// A deleted expense can be restored, so it has to stay a valid expense: where both people
    /// paid, or both have a share, the two amounts become one, and the split is kept as exact
    /// amounts. A payment between the two keeps its amount; restored, it is a payment to
    /// oneself, which the ledger skips. A recurring expense is only ever deleted for good.
    private func combined(_ record: any SyncTracked, _ fields: SyncFields, old: UUID, new: UUID) -> SyncFields? {
        if record is PaymentRecord { return fields }
        guard let record = record as? ExpenseRecord, let expense = try? Expense(record) else { return nil }
        let both: Set<String> = [old.uuidString, new.uuidString]
        let from = PersonID(rawValue: old)
        let into = PersonID(rawValue: new)
        var result = fields
        if UUIDScanner.uuids(in: record.payersData).isSuperset(of: both) {
            guard let payers = Self.merged(expense.payers, from: from, into: into) else { return nil }
            result.set("payers", RecordCoding.encode(payers))
        }
        if UUIDScanner.uuids(in: record.splitData).isSuperset(of: both) {
            guard let shares = try? SplitCalculator.shares(for: expense.split, total: expense.total),
                  let amounts = Self.merged(shares, from: from, into: into) else { return nil }
            result.set("split", RecordCoding.encode(SplitDefinition.exact(amounts: amounts)))
        }
        return result
    }

    private static func merged(_ amounts: [PersonID: Money], from: PersonID, into: PersonID) -> [PersonID: Money]? {
        var result = amounts
        guard let moved = result.removeValue(forKey: from) else { return result }
        guard let sum = try? (result[into] ?? Money(minorUnits: 0, currencyCode: moved.currencyCode)).adding(moved) else {
            return nil
        }
        result[into] = sum
        return result
    }

    private func replaced(_ fields: SyncFields, old: String, new: String, mergeMembers: Bool) -> SyncFields {
        var result = fields
        for (key, value) in fields.values {
            switch value {
            case .string(let text) where text.uppercased() == old:
                result.set(key, new)
            case .data(let data):
                guard let text = String(data: data, encoding: .utf8), text.contains(old) else { continue }
                var updated = Data(text.replacingOccurrences(of: old, with: new).utf8)
                if mergeMembers && key == "memberIDs", let members = try? RecordCoding.decode([UUID].self, from: updated) {
                    var seen: Set<UUID> = []
                    updated = RecordCoding.encode(members.filter { seen.insert($0).inserted })
                }
                result.set(key, updated)
            default:
                continue
            }
        }
        return result
    }
}

extension SyncTracked {
    var recordType: SyncRecordType { Self.syncRecordType }
}

extension ChangeTracker {
    /// Every record except people, for rewriting references.
    func allNonPersonRecords() throws -> [any SyncTracked] {
        var all: [any SyncTracked] = []
        all += try context.fetch(FetchDescriptor<GroupRecord>())
        all += try context.fetch(FetchDescriptor<ExpenseRecord>())
        all += try context.fetch(FetchDescriptor<PaymentRecord>())
        all += try context.fetch(FetchDescriptor<CommentRecord>())
        all += try context.fetch(FetchDescriptor<ActivityRecord>())
        all += try context.fetch(FetchDescriptor<RecurringExpenseRecord>())
        return all
    }
}
