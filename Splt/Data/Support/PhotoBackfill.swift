import Foundation
import SwiftData

/// Before 1.1 only a receipt's file name synced, so the photo stayed on the phone that took it.
/// Once, after updating, every expense whose receipt is on this device and every group whose cover is
/// here are queued for upload, and sync sends the photo with them.
///
/// The records keep their modified date. A newer edit made elsewhere must still win a conflict
/// against this upload, so a photo is never a reason to bring an older version back.
@MainActor
enum PhotoBackfill {
    static let doneKey = "sync.photoBackfillDone"

    /// Runs the pass unless it already ran on this device.
    static func runOnce(
        tracker: ChangeTracker, receipts: PhotoStore = .receipts, covers: PhotoStore = .covers,
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: doneKey) else { return }
        do {
            try queue(tracker: tracker, receipts: receipts, covers: covers)
            defaults.set(true, forKey: doneKey)
        } catch {
            // tried again at the next launch
        }
    }

    /// Queues the records whose photo is on this device. Returns how many were queued.
    @discardableResult
    static func queue(tracker: ChangeTracker, receipts: PhotoStore, covers: PhotoStore) throws -> Int {
        let context = tracker.context
        var count = 0
        let expenses = try context.fetch(FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.receiptFileName != nil && $0.deletedAt == nil }
        ))
        for expense in expenses where expense.pendingOperation != .delete {
            guard let name = expense.receiptFileName, receipts.exists(name) else { continue }
            tracker.recordBookkeeping(expense)
            count += 1
        }
        let groups = try context.fetch(FetchDescriptor<GroupRecord>(
            predicate: #Predicate { $0.coverFileName != nil && $0.deletedAt == nil }
        ))
        for group in groups where group.pendingOperation != .delete {
            guard let name = group.coverFileName, covers.exists(name) else { continue }
            tracker.recordBookkeeping(group)
            count += 1
        }
        try tracker.save()
        return count
    }
}
