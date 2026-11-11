import Foundation
import SpltCore
import SwiftData
import Testing
import UIKit
@testable import Splt

@MainActor
@Suite("Backup and restore")
struct BackupRestoreTests {
    /// A device with every kind of record, a receipt photo with a location, an edited and a deleted
    /// expense, and a group with a cover photo and a default split.
    private struct Source {
        let populated: PopulatedDevice
        let receipt: String
        let cover: String
        let lunch: Expense

        var device: SyncDevice { populated.device }
    }

    private func jpeg(_ color: UIColor = .systemTeal) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).jpegData(withCompressionQuality: 0.8) { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
    }

    private func source() throws -> Source {
        let populated = try PopulatedDevice()
        try populated.addEverythingElse()
        let device = populated.device
        let services = device.services
        let receipt = try device.photos.store(.receipts).save(jpeg(.systemOrange))
        let cover = try device.photos.store(.covers).save(jpeg())

        var lunch = Expense(
            groupID: populated.group.id, title: "Lunch", total: usdAmount(4500), date: device.clock.start,
            paidBy: populated.sam.id, split: .equal(participants: [populated.me.id, populated.sam.id, populated.priya.id])
        )
        try services.expenses.add(lunch, extras: ExpenseExtras(
            receiptFileName: receipt, location: ExpenseLocation(name: "Cafe", latitude: 38.7, longitude: -9.1)
        ))
        lunch.title = "Long Lunch"
        try services.expenses.update(lunch)
        let mistake = try populated.addExpense("Mistake", cents: 100)
        try services.expenses.delete(id: mistake.id)

        let tracker = device.tracker
        let group = try #require(try GroupRecord.find(recordName: populated.zone, in: tracker.context))
        group.coverFileName = cover
        group.defaultSplitData = RecordCoding.encode(DefaultSplit(
            method: .shares, weights: [populated.me.id: 100, populated.sam.id: 150, populated.priya.id: 100]
        ))
        tracker.recordEdit(group)
        try tracker.save()
        return Source(populated: populated, receipt: receipt, cover: cover, lunch: lunch)
    }

    private func writer(_ device: SyncDevice) -> BackupWriter {
        BackupWriter(
            context: device.services.environment.context,
            receipts: device.photos.store(.receipts), covers: device.photos.store(.covers)
        )
    }

    private func restorer(_ device: SyncDevice) -> BackupRestorer {
        BackupRestorer(
            environment: device.services.environment,
            receipts: device.photos.store(.receipts), covers: device.photos.store(.covers)
        )
    }

    /// Writes the file the way the app does and reads it back.
    private func backup(of device: SyncDevice, photos: Bool = true) throws -> BackupDocument {
        let contents = try writer(device).contents(now: device.clock.start, appVersion: "test")
        let directory = FileManager.default.temporaryDirectory.appending(path: "BackupTests-" + UUID().uuidString)
        let url = try BackupFileJob(contents: contents, includesPhotos: photos, directory: directory).write()
        defer { try? FileManager.default.removeItem(at: directory) }
        return try BackupDocument.decode(Data(contentsOf: url))
    }

    private func emptyDevice() throws -> (device: SyncDevice, me: Person) {
        let device = try SyncDevice(start: 1_760_000_000)
        let me = try device.services.people.ensureMe(name: "Me")
        return (device, me)
    }

    /// The map a restore on a device with `me` should use.
    private func expectedMap(from source: SyncDevice, sourceMe: PersonID, to me: PersonID) throws -> BackupIDMap {
        var map = BackupIDMap(salt: me.rawValue)
        map.set(sourceMe.rawValue, to: me.rawValue)
        for case let claim as ItemClaimRecord in try source.tracker.allNonPersonRecords() {
            map.set(claim.id, to: ItemClaimRecord.claimID(expenseID: map[claim.expenseID], personID: map[claim.personID]))
        }
        return map
    }

    /// Every record name on the device, with whether it waits to upload, to show that nothing changed.
    private func snapshot(_ device: SyncDevice) throws -> [String] {
        let tracker = device.tracker
        var records: [any SyncTracked] = try tracker.allNonPersonRecords()
        records += try tracker.context.fetch(FetchDescriptor<PersonRecord>())
        return records.map { "\($0.recordName) \($0.isDirty) \($0.modifiedAt.timeIntervalSinceReferenceDate)" }.sorted()
    }

    private func balancesByName(_ device: SyncDevice, group: GroupID) throws -> [String: Int64] {
        let ledger = try device.services.environment.freshLedger(forGroup: group)
        let names = Dictionary(try device.services.people.allPeople().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(
            (ledger.netBalances["USD"] ?? [:]).map { (names[$0.key] ?? "?", $0.value.minorUnits) }, uniquingKeysWith: +
        )
    }

    private func files(in store: PhotoStore) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []).filter { $0.hasSuffix(".jpg") }
    }

    // MARK: Round trip

    @Test func roundTripRestoresEveryRecordWithNewIDsConsistently() throws {
        let source = try source()
        let document = try backup(of: source.device)
        let (target, me) = try emptyDevice()

        let summary = try restorer(target).restore(document)
        #expect(summary.groupsRestored == 1)
        #expect(summary.groupsAlreadyHere == 0)
        #expect(summary.people == 2)
        #expect(summary.photos == 2)

        let map = try expectedMap(from: source.device, sourceMe: source.populated.me.id, to: me.id)
        let originals = try source.device.tracker.allNonPersonRecords()
        let restored = try target.tracker.allNonPersonRecords()
        #expect(restored.count == originals.count)
        let restoredByName = Dictionary(uniqueKeysWithValues: restored.map { ($0.recordName, $0) })
        let zone = map[source.populated.group.id.rawValue].uuidString

        for original in originals {
            let id = map[try #require(UUID(uuidString: original.recordName))].uuidString
            let copy = try #require(restoredByName[id], "\(original.recordType) \(original.recordName)")
            var expected = map.remapped(original.syncFields)
            var actual = copy.syncFields
            for key in ["receiptFileName", "coverFileName"] {
                expected.set(key, nil as String?)
                actual.set(key, nil as String?)
            }
            #expect(actual == expected, "\(original.recordType)")
            #expect(copy.deletedAt == original.deletedAt)
            #expect(copy.zoneName == zone)
        }

        // no id from the source is left anywhere, inside blobs included
        var sourceIDs = Set(originals.map { $0.recordName.uppercased() })
        sourceIDs.formUnion([source.populated.sam, source.populated.priya, source.populated.me].map { $0.id.rawValue.uuidString })
        for record in restored {
            #expect(record.syncFields.referencedUUIDs.isDisjoint(with: sourceIDs), "\(record.recordType)")
        }

        let people = try target.services.people.allPeople()
        #expect(Set(people.map(\.name)) == ["Me", "Sam", "Priya"])
        let sam = try #require(people.first { $0.name == "Sam" })
        #expect(sam.id.rawValue == map[source.populated.sam.id.rawValue])
        #expect(sam.kind == .placeholder)
        #expect(sam.contactHint == "sam@example.com")
        #expect(sam.avatarSeed == source.populated.sam.avatarSeed)
        #expect(try target.services.people.me()?.id == me.id)

        let newGroup = GroupID(rawValue: map[source.populated.group.id.rawValue])
        #expect(try balancesByName(target, group: newGroup) == balancesByName(source.device, group: source.populated.group.id))
        let group = try #require(try target.services.groups.group(id: newGroup))
        #expect(group.memberIDs.contains(me.id))
    }

    @Test func idsInsideSplitsDefaultSplitAndHistoryPointAtRestoredPeople() throws {
        let source = try source()
        let (target, me) = try emptyDevice()
        try restorer(target).restore(try backup(of: source.device))

        let people = Set(try target.services.people.allPeople().map(\.id))
        let context = target.services.environment.context
        let lunchRecord = try #require(try context.fetch(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.title == "Long Lunch" })).first)
        let lunch = try Expense(lunchRecord)
        #expect(Set(lunch.payers.keys).isSubset(of: people))
        #expect(lunch.split.participants.isSubset(of: people))
        #expect(lunch.split.participants.contains(me.id))
        #expect(lunchRecord.locationName == "Cafe")
        #expect(lunchRecord.latitude == 38.7)
        let history = try RecordCoding.decode([ExpenseEditEntry].self, from: lunchRecord.editHistoryData)
        #expect(!history.isEmpty)

        let group = try #require(try context.fetch(FetchDescriptor<GroupRecord>()).first)
        let split = try RecordCoding.decode(DefaultSplit.self, from: try #require(group.defaultSplitData))
        #expect(Set(split.weights.keys) == people)

        let claim = try #require(try context.fetch(FetchDescriptor<ItemClaimRecord>()).first)
        #expect(claim.id == ItemClaimRecord.claimID(expenseID: claim.expenseID, personID: claim.personID))
        #expect(people.contains(PersonID(rawValue: claim.personID)))
        #expect(try ExpenseRecord.find(recordName: claim.expenseID.uuidString, in: context) != nil)
    }

    // MARK: Groups already here

    @Test func groupAlreadyHereIsSkippedWithEverythingInIt() throws {
        let source = try source()
        let document = try backup(of: source.device)
        let before = try snapshot(source.device)

        let plan = try restorer(source.device).plan(for: document)
        #expect(plan.groupsToRestore == 0)
        #expect(plan.groupsAlreadyHere == ["Flat"])
        #expect(!plan.canRestore)

        let summary = try restorer(source.device).restore(document)
        #expect(summary.groupsRestored == 0)
        #expect(summary.groupsAlreadyHere == 1)
        #expect(try snapshot(source.device) == before)
    }

    @Test func restoringTheSameBackupTwiceAddsNothingTheSecondTime() throws {
        let source = try source()
        let document = try backup(of: source.device)
        let (target, _) = try emptyDevice()
        try restorer(target).restore(document)
        let before = try snapshot(target)

        #expect(try restorer(target).plan(for: document).groupsAlreadyHere == ["Flat"])
        let summary = try restorer(target).restore(document)
        #expect(summary.groupsRestored == 0)
        #expect(summary.people == 0)
        #expect(try snapshot(target) == before)
    }

    @Test func deletedGroupWithTheSameIDIsSkippedAndOthersAreRestored() throws {
        let source = try source()
        let services = source.device.services
        let trip = SplitGroup(name: "Trip", currencyCode: "USD", memberIDs: [source.populated.me.id, source.populated.priya.id])
        try services.groups.create(trip)
        try services.expenses.add(Expense(
            groupID: trip.id, title: "Ferry", total: usdAmount(2000), date: source.device.clock.start,
            paidBy: source.populated.priya.id, split: .equal(participants: [source.populated.me.id, source.populated.priya.id])
        ))
        let document = try backup(of: source.device)

        let (target, _) = try emptyDevice()
        let tracker = target.tracker
        let deleted = GroupRecord.blank(recordName: source.populated.zone)
        deleted.deletedAt = target.clock.start
        tracker.context.insert(deleted)
        try tracker.save()

        let summary = try restorer(target).restore(document)
        #expect(summary.groupsRestored == 1)
        #expect(summary.groupsAlreadyHere == 1)
        let titles = try tracker.context.fetch(FetchDescriptor<ExpenseRecord>()).map(\.title)
        #expect(titles == ["Ferry"])
        // only the people Trip names are added; Sam is only in Flat
        #expect(Set(try target.services.people.allPeople().map(\.name)) == ["Me", "Priya"])
    }

    // MARK: Photos

    @Test func photosComeBackUnderNewNames() throws {
        let source = try source()
        let (target, _) = try emptyDevice()
        try restorer(target).restore(try backup(of: source.device))

        let context = target.services.environment.context
        let lunch = try #require(try context.fetch(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.title == "Long Lunch" })).first)
        let receipt = try #require(lunch.receiptFileName)
        #expect(receipt != source.receipt)
        #expect(target.photos.store(.receipts).image(named: receipt) == source.device.photos.store(.receipts).image(named: source.receipt))

        let group = try #require(try context.fetch(FetchDescriptor<GroupRecord>()).first)
        let cover = try #require(group.coverFileName)
        #expect(cover != source.cover)
        #expect(target.photos.store(.covers).image(named: cover) == source.device.photos.store(.covers).image(named: source.cover))
    }

    @Test func withoutPhotosNoRecordNamesAMissingPhoto() throws {
        let source = try source()
        let document = try backup(of: source.device, photos: false)
        #expect(document.photos.isEmpty)
        let (target, _) = try emptyDevice()
        let summary = try restorer(target).restore(document)
        #expect(summary.photos == 0)
        let context = target.services.environment.context
        #expect(try context.fetch(FetchDescriptor<ExpenseRecord>()).allSatisfy { $0.receiptFileName == nil })
        #expect(try context.fetch(FetchDescriptor<GroupRecord>()).allSatisfy { $0.coverFileName == nil })
    }

    @Test func estimateCountsPhotosOnlyWhenIncluded() throws {
        let source = try source()
        let contents = try writer(source.device).contents(now: source.device.clock.start, appVersion: "test")
        #expect(contents.photos.count == 2)
        #expect(contents.photoBytes > 0)
        // no sync bookkeeping and no iCloud user in the file
        let text = String(decoding: try contents.document.encoded(), as: UTF8.self)
        for word in ["systemFields", "isDirty", "zoneName", "pendingOperation", "claimedByCloudUserID", "recordName"] {
            #expect(!text.contains(word), "\(word)")
        }
    }

    // MARK: Files that can't be restored

    @Test func damagedOrNewerFilesAreRefused() throws {
        let source = try source()
        let data = try backup(of: source.device).encoded()
        #expect(throws: BackupError.unreadable) { try BackupDocument.decode(data.prefix(data.count / 2)) }
        #expect(throws: BackupError.unreadable) { try BackupDocument.decode(Data(#"{"name":"Flat"}"#.utf8)) }
        #expect(throws: BackupError.unreadable) { try BackupDocument.decode(Data()) }

        var newer = try backup(of: source.device)
        newer.formatVersion = BackupDocument.currentVersion + 1
        newer.groups = []
        #expect(throws: BackupError.newerVersion) { try BackupDocument.decode(try newer.encoded()) }
    }

    @Test func craftedFilesChangeNothing() throws {
        let source = try source()
        let original = try backup(of: source.device)
        let (target, _) = try emptyDevice()
        let before = try snapshot(target)

        var huge = original
        huge.groups[0].expenses[0].fields["totalMinorUnits"] = .int(.max)
        var outside = original
        outside.groups[0].payments[0].fields["groupID"] = .string(UUID().uuidString)
        var twice = original
        twice.groups[0].expenses.append(twice.groups[0].expenses[0])
        var hugeSplit = original
        hugeSplit.groups[0].expenses[0].fields["payers"] = .data(Data(#"{"x":{"minorUnits":1e30,"currencyCode":"USD"}}"#.utf8))

        for crafted in [huge, outside, twice, hugeSplit] {
            #expect(throws: BackupError.self) { try BackupDocument.decode(try crafted.encoded()) }
            #expect(throws: BackupError.self) { try restorer(target).restore(crafted) }
        }
        #expect(try snapshot(target) == before)
        #expect(files(in: target.photos.store(.receipts)).isEmpty)
        #expect(files(in: target.photos.store(.covers)).isEmpty)
    }

    @Test func fileNamesInTheFileAreNeverUsedAsPaths() throws {
        let source = try source()
        var document = try backup(of: source.device)
        let index = try #require(document.groups[0].expenses.firstIndex { $0.fields["receiptFileName"] != nil })
        let escape = "../../../Library/escape.jpg"
        document.groups[0].expenses[index].fields["receiptFileName"] = .string(escape)
        document.photos = [
            BackupPhoto(folder: .receipts, name: escape, data: jpeg()),
            BackupPhoto(folder: .covers, name: source.cover, data: Data("not a photo".utf8))
        ]
        let (target, _) = try emptyDevice()
        let summary = try restorer(target).restore(document)

        let receipts = target.photos.store(.receipts)
        let context = target.services.environment.context
        let restored = try #require(try context.fetch(FetchDescriptor<ExpenseRecord>()).compactMap(\.receiptFileName).first)
        #expect(UUID(uuidString: String(restored.dropLast(4))) != nil)
        #expect(files(in: receipts) == [restored])
        #expect(!FileManager.default.fileExists(atPath: receipts.directory.appending(path: escape).standardizedFileURL.path))
        // a photo that isn't an image is left out, and the group shows its symbol
        #expect(try context.fetch(FetchDescriptor<GroupRecord>()).first?.coverFileName == nil)
        #expect(summary.photos == 1)
    }

    // MARK: Sync

    @Test func restoredRecordsAreQueuedForSync() throws {
        let source = try source()
        let (target, me) = try emptyDevice()
        try target.tracker.save()
        let before = Set(try target.tracker.pendingChanges().map(\.recordName))
        try restorer(target).restore(try backup(of: source.device))

        let tracker = target.tracker
        let pending = try tracker.pendingChanges().filter { !before.contains($0.recordName) }
        let restored = try tracker.allNonPersonRecords()
        #expect(Set(pending.map(\.recordName)).isSuperset(of: restored.map(\.recordName)))
        #expect(pending.allSatisfy { $0.operation == .save })
        let zone = BackupIDMap.derived(source.populated.group.id.rawValue, salt: me.id.rawValue).uuidString
        #expect(pending.filter { $0.recordType != .person }.allSatisfy { $0.zoneName == zone })
        #expect(pending.filter { $0.recordType == .person }.count == 2)
        // and the engine can build every upload
        #expect(try target.outgoing().records.count >= restored.count)
    }

    @Test func openingABackupFromFilesShowsItInAccount() {
        let router = Router()
        let url = URL(fileURLWithPath: "/private/var/mobile/Splt Backup 2026-11-10.spltbackup")
        #expect(router.open(url))
        #expect(router.openedBackup?.url == url)
        #expect(router.sheet == .account)

        let busy = Router()
        busy.hasUnsavedForm = true
        busy.present(.addExpense)
        #expect(busy.open(url))
        #expect(busy.sheet == .addExpense)
        #expect(busy.openedBackup?.url == url)
    }

    @Test func fileNameCarriesTheDate() {
        let date = Date(timeIntervalSince1970: 1_794_312_000) // 2026-11-10 12:00 UTC
        #expect(BackupDocument.fileName(for: date, timeZone: TimeZone(identifier: "UTC")!) == "Splt Backup 2026-11-10.spltbackup")
    }
}
