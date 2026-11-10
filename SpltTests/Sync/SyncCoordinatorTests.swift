import CloudKit
import Foundation
import SpltCore
import Synchronization
import Testing
@testable import Splt

/// Records what a coordinator asked an engine to queue.
@MainActor
final class FakeQueue: EngineQueue {
    private(set) var plans: [OutgoingPlan] = []
    private(set) var savedAgain: [CKRecord.ID] = []
    private(set) var zonesRequested: [CKRecordZone.ID] = []

    func queue(_ plan: OutgoingPlan) { plans.append(plan) }
    func queue(saves: [CKRecord.ID]) { savedAgain += saves }
    func queue(zonesToSave: [CKRecordZone.ID]) { zonesRequested += zonesToSave }
    private(set) var fetchCount = 0
    var onFetch: (() throws -> Void)?
    func sendChanges() async throws {}
    func fetchChanges() async throws {
        fetchCount += 1
        try onFetch?()
    }
}

/// A thread safe list that closures can append to.
final class Recorder<Element: Sendable>: Sendable {
    private let box = Mutex<[Element]>([])

    func append(_ element: Element) {
        box.withLock { $0.append(element) }
    }

    var values: [Element] { box.withLock { $0 } }
    var count: Int { values.count }
}

@MainActor
@Suite("Sync coordinator")
struct SyncCoordinatorTests {
    @MainActor
    private struct Rig {
        let populated: PopulatedDevice
        let coordinator: SyncCoordinator
        let privateQueue = FakeQueue()
        let sharedQueue = FakeQueue()
        let delays = Recorder<TimeInterval>()
        let retryRuns = Recorder<Int>()

        var device: SyncDevice { populated.device }

        init(populated: PopulatedDevice) {
            self.populated = populated
            let delays = self.delays
            let runs = self.retryRuns
            let coordinator = SyncCoordinator(services: populated.device.services, adapter: populated.device.adapter)
            coordinator.setRetry(RetryScheduler(
                sleep: { seconds in delays.append(seconds) },
                action: { runs.append(1) }
            ))
            coordinator.attach(privateQueue, for: .privateDatabase)
            coordinator.attach(sharedQueue, for: .sharedDatabase)
            self.coordinator = coordinator
        }
    }

    private func rig(expenses: Bool = true) throws -> Rig {
        let populated = try PopulatedDevice()
        if expenses { try populated.addExpense() }
        return Rig(populated: populated)
    }

    @Test func nothingIsQueuedBeforeTheFirstFetch() throws {
        let rig = try rig()
        try rig.coordinator.reconcile()
        #expect(rig.privateQueue.plans.isEmpty)
        rig.coordinator.markReady()
        try rig.coordinator.reconcile()
        #expect(rig.privateQueue.plans.count == 1)
        #expect(rig.sharedQueue.plans.isEmpty)
    }

    @Test func plansAreSplitByDatabase() throws {
        let rig = try rig()
        let shared = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: "_owner")
        rig.device.adapter.registerZone(shared)
        rig.coordinator.markReady()
        try rig.coordinator.reconcile()
        #expect(rig.privateQueue.plans.isEmpty)
        #expect(rig.sharedQueue.plans.count == 1)
        #expect(rig.sharedQueue.plans[0].saves.allSatisfy { $0.zoneID == shared })
    }

    @Test func startingAdoptsTheIdentityOfTheICloudUser() throws {
        let rig = try rig(expenses: false)
        try rig.coordinator.begin(user: "_alice")
        let expected = CloudIdentity.personID(forUserRecordName: "_alice")
        #expect(try rig.device.services.people.me()?.id == expected)
        #expect(rig.device.adapter.metadata.userRecordName == "_alice")
        #expect(try rig.device.services.groups.group(id: rig.populated.group.id)?.memberIDs.contains(expected) == true)
    }

    @Test func aDifferentICloudUserStartsWithCleanSyncState() throws {
        let rig = try rig()
        try rig.coordinator.begin(user: "_alice")
        rig.coordinator.markReady()
        try rig.coordinator.reconcile()
        try rig.coordinator.begin(user: "_bob")
        #expect(rig.device.adapter.metadata.userRecordName == "_bob")
        #expect(try rig.device.tracker.pendingChanges().isEmpty)
    }

    @Test func aConflictWonLocallyIsQueuedAgainOnTheRightDatabase() throws {
        let rig = try rig()
        let expense = try #require(try rig.device.services.expenses.expenses(in: rig.populated.group.id).first)
        let cloud = FakeCloud()
        try cloud.upload(from: rig.device)
        var edited = expense
        edited.title = "Newer local title"
        try rig.device.services.expenses.update(edited)
        let sent = try #require(try rig.device.outgoing().records.first { $0.recordType == "Expense" })
        var older = try RecordMapper.payload(from: sent)
        older.modifiedAt = older.modifiedAt.addingTimeInterval(-1_000)
        let server = RecordMapper.record(for: older, in: sent.recordID.zoneID, systemFields: older.systemFields)
        let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])
        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [(sent, error)], deleted: [], failedDeletes: [:], scope: .privateDatabase
        )
        #expect(rig.privateQueue.savedAgain == [sent.recordID])
        #expect(rig.sharedQueue.savedAgain.isEmpty)
        #expect(rig.coordinator.status == .idle)
    }

    /// A server copy this device does not believe. Anyone in a shared group can save one.
    enum RefusedCopy: CaseIterable {
        case noModifiedDate, dateFarAhead, amountAboveTheLimit

        func spoil(_ record: CKRecord) {
            switch self {
            case .noModifiedDate: record[RecordSchema.modifiedAtKey] = nil
            case .dateFarAhead: record[RecordSchema.modifiedAtKey] = Date(timeIntervalSinceReferenceDate: 1e14) as NSDate
            case .amountAboveTheLimit: record["totalMinorUnits"] = NSNumber(value: Int64.max)
            }
        }
    }

    /// An edited expense as it was just sent, and the copy the server answers the conflict with.
    private func conflict(_ rig: Rig, serverType: String = "Expense") throws -> (sent: CKRecord, server: CKRecord, marker: CKRecord.ID) {
        rig.coordinator.markReady()
        let expense = try #require(try rig.device.services.expenses.expenses(in: rig.populated.group.id).first)
        try FakeCloud().upload(from: rig.device)
        var edited = expense
        edited.title = "Newer local title"
        try rig.device.services.expenses.update(edited)
        let sent = try #require(try rig.device.outgoing().records.first { $0.recordType == "Expense" })
        let server = CKRecord(recordType: serverType, recordID: sent.recordID)
        for key in sent.allKeys() { server[key] = sent[key] }
        server["title"] = "Forged" as NSString
        // the parent is a system field, so it shows which copy the next upload is built on
        let marker = CKRecord.ID(recordName: "marker", zoneID: sent.recordID.zoneID)
        server.parent = CKRecord.Reference(recordID: marker, action: .none)
        return (sent, server, marker)
    }

    @Test(arguments: RefusedCopy.allCases)
    func aConflictWithACopyThatIsRefusedEndsAfterOneMoreSend(refused: RefusedCopy) throws {
        let rig = try rig()
        let (sent, server, marker) = try conflict(rig)
        refused.spoil(server)
        let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])
        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [(sent, error)], deleted: [], failedDeletes: [:], scope: .privateDatabase
        )
        #expect(rig.privateQueue.savedAgain == [sent.recordID])

        let next = try #require(try rig.device.adapter.outgoingRecord(for: sent.recordID))
        #expect(next.parent?.recordID == marker)
        #expect(next["title"] as? String == "Newer local title")
        try rig.coordinator.sentRecords(saved: [next], failedSaves: [], deleted: [], failedDeletes: [:], scope: .privateDatabase)
        #expect(try rig.device.tracker.pendingChanges().filter { $0.recordType == .expense }.isEmpty)
        #expect(try rig.device.services.expenses.expense(id: ExpenseID(rawValue: try #require(UUID(uuidString: sent.recordID.recordName))))?.title == "Newer local title")
        #expect(rig.coordinator.status == .idle)
    }

    @Test func aConflictWithARecordOfAnotherTypeIsShownInsteadOfSentAgainAtOnce() throws {
        let rig = try rig()
        let (sent, server, _) = try conflict(rig, serverType: "Payment")
        RefusedCopy.noModifiedDate.spoil(server)
        let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])
        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [(sent, error)], deleted: [], failedDeletes: [:], scope: .privateDatabase
        )
        #expect(rig.privateQueue.savedAgain.isEmpty)
        #expect(rig.privateQueue.plans.isEmpty)
        #expect(rig.coordinator.status == .error(SyncFailure.genericMessage))
        #expect(try rig.device.tracker.pendingChanges().contains { $0.recordType == .expense })
    }

    @Test func fullStorageIsShownAndRetriedLaterWithoutLosingChanges() async throws {
        let rig = try rig()
        let sent = try #require(try rig.device.outgoing().records.first)
        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [(sent, CKError(.quotaExceeded))], deleted: [], failedDeletes: [:], scope: .privateDatabase
        )
        guard case .error(let message) = rig.coordinator.status else {
            Issue.record("expected an error status")
            return
        }
        #expect(message.contains("storage"))
        #expect(try rig.device.tracker.pendingChanges().isEmpty == false)
        #expect(await eventually { rig.retryRuns.count == 1 })
        #expect(rig.delays.values == [600])

        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [], deleted: [], failedDeletes: [:], scope: .privateDatabase
        )
        #expect(rig.coordinator.status == .idle)
    }

    @Test func offlineFailuresReportOfflineAndBackOffGradually() async throws {
        let rig = try rig()
        let sent = try #require(try rig.device.outgoing().records.first)
        for _ in 0..<3 {
            try rig.coordinator.sentRecords(
                saved: [], failedSaves: [(sent, CKError(.networkUnavailable))], deleted: [], failedDeletes: [:],
                scope: .privateDatabase
            )
            let before = rig.retryRuns.count
            #expect(await eventually { rig.retryRuns.count > before })
        }
        #expect(rig.coordinator.status == .offline)
        #expect(rig.delays.values == [15, 30, 60])
    }

    @Test func aMissingZoneIsRequestedAgain() async throws {
        let rig = try rig()
        rig.coordinator.markReady()
        let cloud = FakeCloud()
        try cloud.upload(from: rig.device)
        try rig.populated.addExpense("Another")
        let sent = try #require(try rig.device.outgoing().records.first { $0.recordType == "Expense" })
        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [(sent, CKError(.zoneNotFound))], deleted: [], failedDeletes: [:], scope: .privateDatabase
        )
        #expect(await eventually { rig.privateQueue.zonesRequested.map(\.zoneName) == [rig.populated.zone] })
        #expect(rig.privateQueue.savedAgain == [sent.recordID])
    }

    /// An edit that the server refuses because the zone it belongs to is gone.
    private func failWithMissingZone(_ rig: Rig) throws -> CKRecordZone.ID {
        rig.coordinator.markReady()
        try FakeCloud().upload(from: rig.device)
        try rig.populated.addExpense("Edited offline")
        let sent = try #require(try rig.device.outgoing().records.first { $0.recordType == "Expense" })
        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [(sent, CKError(.zoneNotFound))], deleted: [], failedDeletes: [:], scope: .privateDatabase
        )
        return sent.recordID.zoneID
    }

    @Test func aGroupDeletedOnAnotherDeviceIsNotBroughtBackByAnOfflineEdit() async throws {
        let rig = try rig()
        let zone = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: CKCurrentUserDefaultName)
        rig.privateQueue.onFetch = { try rig.coordinator.fetchedZones(modified: [], deleted: [(zone, .deleted)]) }
        _ = try failWithMissingZone(rig)
        #expect(await eventually { rig.privateQueue.fetchCount == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(rig.privateQueue.zonesRequested.isEmpty)
        #expect(rig.privateQueue.savedAgain.isEmpty)
        #expect(try rig.device.services.groups.group(id: rig.populated.group.id) == nil)
        #expect(try rig.device.tracker.pendingChanges().allSatisfy { $0.recordType == .person })
    }

    @Test func aMissingZoneWaitsWhenTheFetchFails() async throws {
        let rig = try rig()
        rig.privateQueue.onFetch = { throw CKError(.networkUnavailable) }
        _ = try failWithMissingZone(rig)
        #expect(await eventually { rig.privateQueue.fetchCount == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(rig.privateQueue.zonesRequested.isEmpty)
        #expect(try rig.device.services.groups.group(id: rig.populated.group.id) != nil)
    }

    @Test func aZoneTheServerNeverConfirmedIsRequestedWithoutAFetch() throws {
        let rig = try rig()
        rig.coordinator.markReady()
        let sent = try #require(try rig.device.outgoing().records.first { $0.recordType == "Expense" })
        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [(sent, CKError(.zoneNotFound))], deleted: [], failedDeletes: [:], scope: .privateDatabase
        )
        #expect(rig.privateQueue.zonesRequested.map(\.zoneName) == [rig.populated.zone])
        #expect(rig.privateQueue.savedAgain == [sent.recordID])
        #expect(rig.privateQueue.fetchCount == 0)
    }

    @Test func remoteChangesAreReportedToTheNotifier() throws {
        let rig = try rig()
        let cloud = FakeCloud()
        try cloud.upload(from: rig.device)
        let other = try SyncDevice()
        let coordinator = SyncCoordinator(services: other.services, adapter: other.adapter)
        var reports: [ApplyReport] = []
        coordinator.onRemoteChanges = { reports.append($0) }
        try coordinator.fetchedRecords(modifications: Array(cloud.records.values), deletions: [])
        #expect(reports.count == 1)
        #expect(reports[0].inserted.contains { $0.recordType == .activity })
    }

    @Test func joiningASharedGroupAddsYouAsAMemberAndImportsNobodyElseTwice() throws {
        let owner = try PopulatedDevice()
        try owner.addExpense()
        let cloud = FakeCloud()
        try cloud.upload(from: owner.device)

        let joiner = try SyncDevice()
        let joinerMe = try joiner.services.people.ensureMe(name: "Casey")
        let coordinator = SyncCoordinator(services: joiner.services, adapter: joiner.adapter)
        try coordinator.begin(user: "_casey")
        let sharedZone = CKRecordZone.ID(zoneName: owner.zone, ownerName: "_owner")
        let moved = try cloud.records.values.map { record -> CKRecord in
            var payload = try RecordMapper.payload(from: record)
            payload.systemFields = nil
            return RecordMapper.record(for: payload, in: sharedZone)
        }
        try coordinator.fetchedZones(modified: [sharedZone], deleted: [])
        try coordinator.fetchedRecords(modifications: moved, deletions: [])

        let casey = CloudIdentity.personID(forUserRecordName: "_casey")
        let group = try #require(try joiner.services.groups.group(id: owner.group.id))
        #expect(group.memberIDs.contains(casey))
        #expect(try joiner.services.people.me()?.id == casey)
        #expect(joinerMe.id != casey)
        let dirty = try joiner.tracker.pendingChanges()
        #expect(dirty.contains { $0.recordType == .group })
    }

    @Test func aPurgedZoneIsQueuedForUploadAgain() throws {
        let rig = try rig()
        rig.coordinator.markReady()
        let cloud = FakeCloud()
        try cloud.upload(from: rig.device)
        let zone = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: CKCurrentUserDefaultName)
        try rig.coordinator.fetchedZones(modified: [], deleted: [(zone, .purged)])
        #expect(rig.privateQueue.plans.count == 1)
        #expect(rig.privateQueue.plans[0].zonesToSave == [zone])
    }

    @Test func signingOutShowsNoAccountAndSigningBackInClearsIt() throws {
        let rig = try rig(expenses: false)
        try rig.coordinator.accountChanged(.signedOut)
        #expect(rig.coordinator.status == .noAccount)
        try rig.coordinator.accountChanged(.signedIn(user: "_alice"))
        #expect(rig.coordinator.status == .idle)
    }

    @Test func switchingAccountsAdoptsTheNewIdentity() throws {
        let rig = try rig(expenses: false)
        try rig.coordinator.begin(user: "_alice")
        try rig.coordinator.accountChanged(.switched(to: "_bob"))
        #expect(try rig.device.services.people.me()?.id == CloudIdentity.personID(forUserRecordName: "_bob"))
        #expect(rig.device.adapter.metadata.userRecordName == "_bob")
    }

    @Test func aRecordDeletedDuringItsFirstUploadIsDeletedOnTheServer() throws {
        let rig = try rig()
        let device = rig.device
        let cloud = FakeCloud()
        try cloud.upload(from: device)
        let expense = try #require(try device.services.expenses.expenses(in: rig.populated.group.id).first)
        let comment = ExpenseComment(
            groupID: rig.populated.group.id, expenseID: expense.id, authorID: rig.populated.me.id, text: "Soon gone",
            createdAt: device.clock.start
        )
        try device.services.comments.add(comment)
        let (_, sending) = try device.outgoing()
        let inFlight = try #require(sending.first { $0.recordID.recordName == comment.id.uuidString })

        try device.services.comments.delete(id: comment.id)
        try rig.coordinator.sentRecords(saved: sending, failedSaves: [], deleted: [], failedDeletes: [:], scope: .privateDatabase)
        #expect(rig.privateQueue.plans.flatMap(\.deletes) == [inFlight.recordID])
    }

    @Test func aDeleteInAZoneThatIsGoneIsDone() throws {
        let rig = try rig()
        let device = rig.device
        let expense = try #require(try device.services.expenses.expenses(in: rig.populated.group.id).first)
        let comment = ExpenseComment(
            groupID: rig.populated.group.id, expenseID: expense.id, authorID: rig.populated.me.id, text: "Soon gone",
            createdAt: device.clock.start
        )
        try device.services.comments.add(comment)
        try FakeCloud().upload(from: device)
        try device.services.comments.delete(id: comment.id)
        let id = try #require(try device.adapter.collectOutgoing().deletes.first)
        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [], deleted: [], failedDeletes: [id: CKError(.zoneNotFound)], scope: .privateDatabase
        )
        #expect(try device.tracker.pendingChanges().isEmpty)
    }

    /// A device that has joined the owner's group through a share, and the records as its zone holds them.
    @MainActor
    private struct Joiner {
        let owner: PopulatedDevice
        let cloud = FakeCloud()
        let device: SyncDevice
        let coordinator: SyncCoordinator
        let me = CloudIdentity.personID(forUserRecordName: "_casey")

        init(fetching: Bool = true) throws {
            owner = try PopulatedDevice()
            try cloud.upload(from: owner.device)
            device = try SyncDevice()
            try device.services.people.ensureMe(name: "Casey")
            coordinator = SyncCoordinator(services: device.services, adapter: device.adapter)
            try coordinator.begin(user: "_casey")
            guard fetching else { return }
            try coordinator.fetchedZones(modified: [sharedZone], deleted: [])
            try fetch()
        }

        var sharedZone: CKRecordZone.ID { CKRecordZone.ID(zoneName: owner.zone, ownerName: "_owner") }

        func fetch() throws {
            let records = try cloud.records.values.map { record -> CKRecord in
                var payload = try RecordMapper.payload(from: record)
                payload.systemFields = nil
                return RecordMapper.record(for: payload, in: sharedZone)
            }
            try coordinator.fetchedRecords(modifications: records, deletions: [])
        }

        var isMember: Bool {
            get throws { try device.services.groups.group(id: owner.group.id)?.memberIDs.contains(me) == true }
        }

        func ownerRemovesMe() throws {
            let services = owner.device.services
            try services.people.add(Person(id: me, name: "Casey", kind: .friend))
            try services.groups.addMember(me, to: owner.group.id)
            owner.device.clock.advance(by: 1_000)
            try services.groups.removeMember(me, from: owner.group.id)
            try cloud.upload(from: owner.device)
        }
    }

    @Test func someoneTheOwnerRemovedDoesNotAddThemselvesBack() throws {
        let joiner = try Joiner()
        #expect(try joiner.isMember)
        try joiner.ownerRemovesMe()
        try joiner.fetch()
        #expect(try !joiner.isMember)
    }

    @Test func aJoinLostToAConflictIsRepaired() throws {
        let joiner = try Joiner()
        // another member's older copy of the group replaced this device's join, with no removal anywhere
        try joiner.device.tracker.markSynced(
            recordType: .group, recordName: joiner.owner.zone, sentModifiedAt: .distantFuture, systemFields: nil
        )
        try joiner.fetch()
        #expect(try joiner.isMember)
    }

    @Test func aNewInvitationBringsBackSomeoneWhoWasRemoved() throws {
        let joiner = try Joiner()
        try joiner.ownerRemovesMe()
        try joiner.fetch()
        try joiner.coordinator.joined(zoneName: joiner.owner.zone)
        #expect(try joiner.isMember)
    }

    @Test func anInvitationAcceptedBeforeTheGroupArrivesStillBringsBackSomeoneWhoWasRemoved() throws {
        let joiner = try Joiner(fetching: false)
        try joiner.ownerRemovesMe()
        try joiner.coordinator.joined(zoneName: joiner.owner.zone)
        #expect(try !joiner.isMember)
        #expect(joiner.device.adapter.metadata.pendingJoins == [joiner.owner.zone])

        try joiner.coordinator.fetchedZones(modified: [joiner.sharedZone], deleted: [])
        try joiner.fetch()
        #expect(try joiner.isMember)
        #expect(joiner.device.adapter.metadata.pendingJoins?.isEmpty == true)
    }

    @Test func changesInASharedGroupYouAreInSayThatYouAreAMember() throws {
        let joiner = try Joiner()
        var groups: [GroupID] = []
        joiner.coordinator.onMembership = { groups.append($0) }
        try joiner.fetch()
        #expect(groups == [joiner.owner.group.id])

        // while leaving, the group stays hidden
        groups = []
        joiner.coordinator.requestLeave(zoneName: joiner.owner.zone)
        try joiner.fetch()
        #expect(groups.isEmpty)
    }

    @Test func changesInAGroupYouWereRemovedFromDoNotSayThatYouAreAMember() throws {
        let joiner = try Joiner()
        var groups: [GroupID] = []
        joiner.coordinator.onMembership = { groups.append($0) }
        try joiner.ownerRemovesMe()
        try joiner.fetch()
        #expect(groups.isEmpty)
    }

    @Test func someoneWithNoProfileYetStillBecomesAMemberWhenTheyJoin() throws {
        let owner = try PopulatedDevice()
        let cloud = FakeCloud()
        try cloud.upload(from: owner.device)
        let device = try SyncDevice()
        let coordinator = SyncCoordinator(services: device.services, adapter: device.adapter)
        try coordinator.begin(user: "_casey")
        let zone = CKRecordZone.ID(zoneName: owner.zone, ownerName: "_owner")
        try coordinator.fetchedZones(modified: [zone], deleted: [])
        let records = try cloud.records.values.map { record -> CKRecord in
            var payload = try RecordMapper.payload(from: record)
            payload.systemFields = nil
            return RecordMapper.record(for: payload, in: zone)
        }
        try coordinator.fetchedRecords(modifications: records, deletions: [])
        let casey = CloudIdentity.personID(forUserRecordName: "_casey")
        #expect(try device.services.groups.group(id: owner.group.id)?.memberIDs.contains(casey) == true)
        #expect(try device.services.people.me()?.id == casey)
    }
}

@MainActor
@Suite("Retry scheduler")
struct RetrySchedulerTests {
    @Test func unrecoverableFailuresAreNotRetried() {
        let scheduler = RetryScheduler(sleep: { _ in }, action: {})
        scheduler.failed(.conflict)
        scheduler.failed(.restricted)
        #expect(!scheduler.isScheduled)
    }

    @Test func successResetsTheCountAndCancelsTheWait() {
        let scheduler = RetryScheduler(sleep: { _ in try? await Task.sleep(for: .seconds(60)) }, action: {})
        scheduler.failed(.offline)
        #expect(scheduler.isScheduled)
        #expect(scheduler.failureCount == 1)
        scheduler.failed(.offline)
        #expect(scheduler.failureCount == 1)
        scheduler.succeeded()
        #expect(!scheduler.isScheduled)
        #expect(scheduler.failureCount == 0)
    }
}

@Suite("Status machine")
struct SyncStatusMachineTests {
    private let send = SyncStatusMachine.Source(scope: .privateDatabase, isSending: true)
    private let fetch = SyncStatusMachine.Source(scope: .sharedDatabase, isSending: false)

    @Test func idleSyncingAndBack() {
        var machine = SyncStatusMachine()
        #expect(machine.status == .idle)
        machine.began()
        machine.began()
        #expect(machine.status == .syncing)
        machine.ended()
        #expect(machine.status == .syncing)
        machine.ended()
        machine.ended()
        #expect(machine.status == .idle)
    }

    @Test func problemsWinOverSyncingAndClearOnSuccess() {
        var machine = SyncStatusMachine()
        machine.began()
        machine.failed(.offline, source: send)
        #expect(machine.status == .offline)
        machine.succeeded(source: send)
        #expect(machine.status == .syncing)
    }

    @Test func accountProblemsOutrankOtherProblems() {
        var machine = SyncStatusMachine()
        machine.failed(.quotaExceeded, source: send)
        machine.failed(.noAccount, source: fetch)
        #expect(machine.status == .noAccount)
        machine.clearProblems()
        #expect(machine.status == .idle)
    }

    @Test func noNetworkPathMeansOffline() {
        var machine = SyncStatusMachine()
        machine.isOnline = false
        #expect(machine.status == .offline)
        machine.isOnline = true
        #expect(machine.status == .idle)
    }

    @Test func transientFailuresAreNotShown() {
        var machine = SyncStatusMachine()
        machine.failed(.transient(retryAfter: 5), source: send)
        machine.failed(.conflict, source: fetch)
        #expect(machine.status == .idle)
    }
}
