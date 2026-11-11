import Foundation
import SpltCore
import SwiftData

/// Adds what a backup holds and this device lacks. It never deletes or changes anything already here.
///
/// - A group that is here, under its own id or as the copy an earlier restore made, live or
///   deleted, is skipped with everything in it.
/// - Any other group becomes a new group of your own, in your iCloud, with every id in it new,
///   also those inside splits, events and history. See `BackupIDMap`.
/// - The backup's "me" becomes this device's "me". Everyone else becomes a new person without the
///   app, as when you add someone by name, and can be claimed when they join.
/// - Every record goes through the change tracker, so it syncs like one you typed in.
/// - It all happens in one save. When anything fails, the store is rolled back and the photos
///   written so far are removed, so a failed restore changes nothing.
@MainActor
struct BackupRestorer {
    let environment: RepositoryContext
    var receipts: PhotoStore = .receipts
    var covers: PhotoStore = .covers

    /// What a backup holds and what restoring it would do, shown before you confirm.
    struct Plan: Equatable, Sendable {
        var createdAt: Date
        var groups: Int
        var expenses: Int
        var payments: Int
        var photos: Int
        var groupsToRestore: Int
        /// The names of the groups that are already here and will be skipped.
        var groupsAlreadyHere: [String]

        var canRestore: Bool { groupsToRestore > 0 }
    }

    /// What a restore added.
    struct Summary: Equatable, Sendable {
        var groupsRestored = 0
        var groupsAlreadyHere = 0
        var expenses = 0
        var payments = 0
        var people = 0
        var photos = 0
        /// The first restored group, to open afterwards.
        var firstGroup: GroupID?
    }

    private var context: ModelContext { environment.context }

    func plan(for document: BackupDocument) throws -> Plan {
        let split = try partition(document, salt: try environment.currentUser()?.id)
        let live = { (records: [BackupRecord]) in records.count(where: { $0.deletedAt == nil }) }
        return Plan(
            createdAt: document.createdAt,
            groups: document.groups.count,
            expenses: document.groups.reduce(0) { $0 + live($1.expenses) },
            payments: document.groups.reduce(0) { $0 + live($1.payments) },
            photos: document.photos.count,
            groupsToRestore: split.restore.count,
            groupsAlreadyHere: split.alreadyHere.map { Self.name(of: $0) }
        )
    }

    @discardableResult
    func restore(_ document: BackupDocument) throws -> Summary {
        try document.validate()
        var written: [(store: PhotoStore, name: String)] = []
        do {
            let summary = try insert(document, written: &written)
            try environment.save()
            return summary
        } catch {
            environment.tracker.rollback()
            for photo in written { photo.store.delete(photo.name) }
            throw (error as? BackupError) ?? BackupError.saveFailed
        }
    }

    // MARK: Steps

    private func insert(_ document: BackupDocument, written: inout [(store: PhotoStore, name: String)]) throws -> Summary {
        let backupMe = document.meID.flatMap { id in document.people.first { $0.id == id } }
        let me = try environment.currentUser() ?? makeMe(named: backupMe?.fields["name"])
        var map = BackupIDMap(salt: me.id)
        if let id = document.meID { map.set(id, to: me.id) }

        let split = try partition(document, salt: me.id)
        addWorkedOutIDs(split.restore, to: &map)
        var summary = Summary(groupsAlreadyHere: split.alreadyHere.count)

        // people first, so the groups that name them never point at nobody
        let needed = Self.mentionedIDs(in: split.restore)
        let inAnyGroup = Self.mentionedIDs(in: document.groups)
        for person in document.people where person.id != document.meID {
            // a friend without a group is only added when they aren't here under either id
            let isOnlyAFriend = !inAnyGroup.contains(person.id)
            guard needed.contains(person.id) || isOnlyAFriend else { continue }
            if isOnlyAFriend, try PersonRecord.find(recordName: person.id.uuidString, in: context) != nil { continue }
            let id = map[person.id]
            guard try PersonRecord.find(recordName: id.uuidString, in: context) == nil else { continue }
            let record = PersonRecord(Self.placeholder(person, id: id, now: environment.now()))
            context.insert(record)
            environment.tracker.recordEdit(record)
            summary.people += 1
        }

        let photos = Dictionary(document.photos.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for group in split.restore {
            let zone = map[group.group.id].uuidString
            for type in BackupGroup.recordTypes {
                for backup in group.records(of: type) {
                    let keepsDeletion = type == .expense || type == .payment
                    // only expenses and payments stay in history when deleted, so anything else deleted is left out
                    if !keepsDeletion, backup.deletedAt != nil { continue }
                    let id = map[backup.id].uuidString
                    // never replace a record that is here, whatever the file says
                    guard try type.modelType.find(recordName: id, in: context) == nil else { continue }

                    var fields = map.remapped(backup.syncFields)
                    if type == .expense {
                        let name = restoredPhoto(backup.fields["receiptFileName"], folder: .receipts, photos: photos, map: map, written: &written)
                        fields.set("receiptFileName", name)
                        if name != nil { summary.photos += 1 }
                    } else if type == .group {
                        let name = restoredPhoto(backup.fields["coverFileName"], folder: .covers, photos: photos, map: map, written: &written)
                        fields.set("coverFileName", name)
                        if name != nil { summary.photos += 1 }
                    }

                    let record = type.modelType.blank(recordName: id)
                    record.applySyncFields(fields)
                    record.zoneName = zone
                    record.deletedAt = keepsDeletion ? backup.deletedAt : nil
                    // what happened in a restored group is history, not news
                    (record as? ActivityRecord)?.isRead = true
                    context.insert(record)
                    environment.tracker.recordEdit(record)

                    switch type {
                    case .group:
                        summary.groupsRestored += 1
                        if summary.firstGroup == nil, let uuid = UUID(uuidString: id) { summary.firstGroup = GroupID(rawValue: uuid) }
                    case .expense where backup.deletedAt == nil: summary.expenses += 1
                    case .payment where backup.deletedAt == nil: summary.payments += 1
                    default: break
                    }
                }
            }
        }
        return summary
    }

    /// Groups to restore, and those already here under their own id or as an earlier restore's copy.
    private func partition(_ document: BackupDocument, salt: UUID?) throws -> (restore: [BackupGroup], alreadyHere: [BackupGroup]) {
        var restore: [BackupGroup] = []
        var alreadyHere: [BackupGroup] = []
        for group in document.groups {
            var names = [group.group.id.uuidString]
            if let salt { names.append(BackupIDMap.derived(group.group.id, salt: salt).uuidString) }
            if try names.contains(where: { try GroupRecord.find(recordName: $0, in: context) != nil }) {
                alreadyHere.append(group)
            } else {
                restore.append(group)
            }
        }
        return (restore, alreadyHere)
    }

    /// Some ids are worked out from others so every device arrives at the same one: a person's claim
    /// on an expense, a recurring expense's occurrence and the activity that announced it. They are
    /// worked out again from the new ids, so the app still finds them.
    private func addWorkedOutIDs(_ groups: [BackupGroup], to map: inout BackupIDMap) {
        for group in groups {
            var announcements: [UUID: UUID] = [:]
            for expense in group.expenses {
                let fields = expense.syncFields
                if let template = fields.uuid("recurringExpenseID"), let date = fields.date("date"),
                   OccurrenceID.expenseID(template: template, occurrence: date).rawValue == expense.id {
                    map.set(expense.id, to: OccurrenceID.expenseID(template: map[template], occurrence: date).rawValue)
                }
                announcements[OccurrenceID.addedEntryID(expense: ExpenseID(rawValue: expense.id))] = expense.id
            }
            for entry in group.activity {
                if let expense = announcements[entry.id] {
                    map.set(entry.id, to: OccurrenceID.addedEntryID(expense: ExpenseID(rawValue: map[expense])))
                }
            }
            for claim in group.itemClaims {
                let fields = claim.syncFields
                guard let expense = fields.uuid("expenseID"), let person = fields.uuid("personID") else { continue }
                map.set(claim.id, to: ItemClaimRecord.claimID(expenseID: map[expense], personID: map[person]))
            }
        }
    }

    /// Saves a photo from the file under a name of the app's own, or reuses the one this device
    /// still has under the old name. Nil when there is no photo to show, so no record names a missing file.
    private func restoredPhoto(
        _ value: BackupValue?, folder: BackupPhoto.Folder, photos: [String: BackupPhoto], map: BackupIDMap,
        written: inout [(store: PhotoStore, name: String)]
    ) -> String? {
        guard case .string(let original)? = value else { return nil }
        let store = folder == .receipts ? receipts : covers
        let name = map.photoName(for: folder, original: original)
        if store.exists(name) { return name }
        let data = photos[folder.rawValue + "/" + original]?.data ?? store.image(named: original)
        guard let data, store.keep(data, named: name) else { return nil }
        written.append((store, name))
        return name
    }

    private func makeMe(named name: BackupValue?) -> PersonRecord {
        var text = String(localized: "Me")
        if case .string(let value)? = name, !value.isEmpty { text = value.limited(to: RecordLimits.name) }
        let record = PersonRecord(Person(name: text, kind: .me, createdAt: environment.now()))
        context.insert(record)
        environment.tracker.recordEdit(record)
        return record
    }

    private static func placeholder(_ backup: BackupRecord, id: UUID, now: Date) -> Person {
        let fields = backup.syncFields
        return Person(
            id: PersonID(rawValue: id),
            name: (fields.string("name") ?? "").limited(to: RecordLimits.name),
            contactHint: fields.string("contactHint")?.limited(to: RecordLimits.name),
            kind: .placeholder,
            avatarSeed: Int(clamping: fields.int("avatarSeed") ?? 0),
            createdAt: fields.date("createdAt") ?? now
        )
    }

    /// Every id the records of these groups mention, in id fields or inside blobs.
    private static func mentionedIDs(in groups: [BackupGroup]) -> Set<UUID> {
        var found: Set<UUID> = []
        for group in groups {
            for type in BackupGroup.recordTypes {
                for record in group.records(of: type) {
                    for text in record.syncFields.referencedUUIDs {
                        if let id = UUID(uuidString: text) { found.insert(id) }
                    }
                }
            }
        }
        return found
    }

    private static func name(of group: BackupGroup) -> String {
        if case .string(let name)? = group.group.fields["name"] { return name }
        return ""
    }
}
