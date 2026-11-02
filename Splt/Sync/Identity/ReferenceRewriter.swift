import Foundation
import SwiftData

enum RewriteResult: Equatable, Sendable {
    /// The number of records that were rewritten and marked for upload.
    case rewritten(Int)
    /// Both ids appear in the same record, so merging them would need to combine amounts. Nothing was changed.
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
                blocked += 1
                continue
            }
            changes.append((record, replaced(fields, old: oldText, new: newText, mergeMembers: isGroup)))
        }
        guard blocked == 0 else { return .blocked(records: blocked) }

        for change in changes {
            change.record.applySyncFields(change.fields)
            if change.record.deletedAt != nil && change.record.pendingOperation == .delete { continue }
            tracker.recordEdit(change.record)
        }
        try tracker.save()
        return .rewritten(changes.count)
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
