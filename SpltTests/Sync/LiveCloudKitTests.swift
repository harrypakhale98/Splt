import CloudKit
import Foundation
import SpltCore
import Testing
@testable import Splt

/// Sync against real iCloud: one account, and two stores standing in for two devices.
///
/// Everything else in this folder runs against stand-ins for CloudKit. This runs the real engine
/// against the real container, in the Development environment, so it needs a signed build on a
/// machine that is signed in to iCloud. It only runs when `SPLT_LIVE_ICLOUD` is set. docs/sync.md
/// says how to run it on a Mac.
///
/// To CloudKit both stores are the same device, and it does not tell a device about a zone that
/// device changed itself. So a change is never looked for on the store next to the one that made
/// it: it is checked on the server, and on a store that starts from nothing and downloads it all.
/// What two real devices add, and sharing between two accounts, is the checklist in docs/sync.md.
@Suite("Live iCloud", .serialized, .enabled(if: ProcessInfo.processInfo.environment["SPLT_LIVE_ICLOUD"] != nil))
@MainActor
struct LiveCloudKitTests {
    /// One store with the real engine on it.
    @MainActor
    private final class Device {
        let local: SyncDevice
        let engine: CloudKitSyncEngine

        var services: DataServices { local.services }

        init(local: SyncDevice, container: String) {
            self.local = local
            engine = CloudKitSyncEngine(
                backend: LiveCloudKitBackend(containerIdentifier: container), services: local.services,
                store: local.store, reconcileDelay: .milliseconds(50)
            )
        }

        /// Sends until nothing is waiting any more. A first send can come back with conflicts to settle.
        func push() async throws {
            for _ in 0..<40 {
                try? await engine.sendChanges()
                if try local.tracker.pendingChanges().isEmpty { return }
                try await Task.sleep(for: .milliseconds(500))
            }
            Issue.record("changes never left this device: \(try local.tracker.pendingChanges().count) still waiting, status \(engine.status)")
        }

        /// Fetches until the condition holds.
        func receives(_ condition: () throws -> Bool) async -> Bool {
            for _ in 0..<40 {
                try? await engine.fetchChanges()
                if (try? condition()) == true { return true }
                try? await Task.sleep(for: .seconds(1))
            }
            return false
        }
    }

    private var container: String? { EntitlementReader.current().cloudKitContainers.first }

    @Test func twoStoresOnOneAccountAgreeThroughICloud() async throws {
        let container = try #require(container, "this build has no iCloud container: run a signed build")
        // real time, so nothing is refused for its date, with B's clock ahead so its edits are the later ones
        let base = Date().timeIntervalSince1970 - 3600
        let populated = try PopulatedDevice(start: base)
        try populated.addEverythingElse()
        try populated.addExpense("Dinner")
        let a = Device(local: populated.device, container: container)
        let b = try freshDevice(start: base + 600, container: container)
        let group = populated.group.id
        let zone = CKRecordZone.ID(zoneName: group.description, ownerName: CKCurrentUserDefaultName)
        let database = CKContainer(identifier: container).privateCloudDatabase
        var devices = [a, b]

        do {
            // A uploads a group with every kind of record in it
            await a.engine.start()
            try await a.push()
            #expect(a.engine.status == .idle, "A after its first upload: \(a.engine.status)")

            // B starts from nothing and downloads all of it
            await b.engine.start()
            try await expectSame(group, on: b, as: a)

            // an edit on B reaches the server
            var expense = try #require(try b.services.expenses.expenses(in: group).first)
            expense.title = "Edited on B"
            try b.services.expenses.update(expense)
            try await b.push()
            let record = CKRecord.ID(recordName: expense.id.description, zoneID: zone)
            #expect(try await database.record(for: record)["title"] as? String == "Edited on B")

            // A has not heard of it and edits the same expense, earlier by its clock: the server's copy wins on A
            var fromA = try #require(try a.services.expenses.expense(id: expense.id))
            fromA.title = "From A"
            try a.services.expenses.update(fromA)
            try await a.push()
            #expect(try a.services.expenses.expense(id: expense.id)?.title == "Edited on B")
            #expect(try await database.record(for: record)["title"] as? String == "Edited on B")

            // the other way round: A changes it on the server behind B's back, B's later edit wins there
            var newer = try #require(try a.services.expenses.expense(id: expense.id))
            newer.note = "A adds a note"
            try a.services.expenses.update(newer)
            try await a.push()
            var fromB = try #require(try b.services.expenses.expense(id: expense.id))
            fromB.title = "From B"
            try b.services.expenses.update(fromB)
            try await b.push()
            #expect(try b.services.expenses.expense(id: expense.id)?.title == "From B")
            #expect(try await database.record(for: record)["title"] as? String == "From B")

            // a delete, then a third store that starts from nothing: it gets the state as it is now
            let doomed = try #require(try b.services.expenses.expenses(in: group).first { $0.id != expense.id })
            try b.services.expenses.delete(id: doomed.id)
            try await b.push()
            let c = try freshDevice(start: base + 1200, container: container)
            devices.append(c)
            await c.engine.start()
            try await expectSame(group, on: c, as: b)
            #expect(try c.services.expenses.expense(id: expense.id)?.title == "From B")
            #expect(try !c.services.expenses.expenses(in: group).contains { $0.id == doomed.id })

            // the owner's side of sharing: first for invited people only, then opened to anyone with the link
            #expect(await !b.engine.isSharedByMe(group: group))
            let invited = try await b.engine.share(group: group, anyoneWithLink: false)
            #expect(invited.url != nil)
            #expect(!invited.isOpenToAnyoneWithLink)
            #expect(try await b.engine.isSharedInviteOnly(group: group))
            let share = try await b.engine.share(group: group, anyoneWithLink: true)
            #expect(share.url == invited.url)
            #expect(share.isOpenToAnyoneWithLink)
            #expect(try await !b.engine.isSharedInviteOnly(group: group))
            #expect(await b.engine.isSharedByMe(group: group))
            // asking again without the link hands back the same share and does not close it
            let again = try await b.engine.share(group: group, anyoneWithLink: false)
            #expect(again.url == share.url)
            #expect(again.isOpenToAnyoneWithLink)

            // deleting the group takes its zone out of iCloud, so a store that starts now never sees it
            try b.services.groups.delete(id: group)
            try await b.push()
            await #expect(throws: CKError.self) { _ = try await database.recordZone(for: zone) }
            let d = try freshDevice(start: base + 1800, container: container)
            devices.append(d)
            await d.engine.start()
            try? await d.engine.fetchChanges()
            #expect(try d.services.groups.group(id: group) == nil)
            #expect(b.engine.status == .idle, "B at the end: \(b.engine.status)")
        } catch {
            await cleanUp(zone, container: container, devices: devices)
            throw error
        }
        await cleanUp(zone, container: container, devices: devices)
    }

    private func freshDevice(start: TimeInterval, container: String) throws -> Device {
        let local = try SyncDevice(start: start)
        try local.services.people.ensureMe(name: "Me")
        return Device(local: local, container: container)
    }

    /// Waits for the group to arrive on `device`, then compares everything in it with `other`.
    private func expectSame(_ group: GroupID, on device: Device, as other: Device) async throws {
        let expected = try other.services.expenses.expenses(in: group)
        #expect(await device.receives {
            try device.services.groups.group(id: group) != nil && device.services.expenses.expenses(in: group).count == expected.count
        }, "the group never arrived whole")
        let mine = try #require(try device.services.groups.group(id: group))
        let theirs = try #require(try other.services.groups.group(id: group))
        #expect(mine.name == theirs.name)
        #expect(Set(mine.memberIDs) == Set(theirs.memberIDs))
        #expect(try device.services.people.people(ids: mine.memberIDs).map(\.name).sorted() == other.services.people.people(ids: theirs.memberIDs).map(\.name).sorted())
        let got = try device.services.expenses.expenses(in: group)
        #expect(Set(got.map(\.id)) == Set(expected.map(\.id)))
        for expense in expected {
            let copy = try #require(got.first { $0.id == expense.id })
            #expect(copy.title == expense.title)
            #expect(copy.total == expense.total)
            #expect(try copy.shares() == expense.shares())
        }
        #expect(try device.services.payments.payments(in: group).map(\.amount) == other.services.payments.payments(in: group).map(\.amount))
        #expect(try device.services.comments.comments(in: group).map(\.text) == other.services.comments.comments(in: group).map(\.text))
        #expect(try device.services.recurring.templates(in: group).map(\.title) == other.services.recurring.templates(in: group).map(\.title))
    }

    /// Leaves nothing behind in iCloud, also when a step failed half way.
    private func cleanUp(_ zone: CKRecordZone.ID, container: String, devices: [Device]) async {
        for device in devices {
            await device.engine.stop()
        }
        _ = try? await CKContainer(identifier: container).privateCloudDatabase.deleteRecordZone(withID: zone)
    }
}
