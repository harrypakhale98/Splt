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
    func sendChanges() async throws {}
    func fetchChanges() async throws {}
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

    @Test func aMissingZoneIsRequestedAgain() throws {
        let rig = try rig()
        rig.coordinator.markReady()
        let cloud = FakeCloud()
        try cloud.upload(from: rig.device)
        try rig.populated.addExpense("Another")
        let sent = try #require(try rig.device.outgoing().records.first { $0.recordType == "Expense" })
        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [(sent, CKError(.zoneNotFound))], deleted: [], failedDeletes: [:], scope: .privateDatabase
        )
        #expect(rig.privateQueue.zonesRequested.map(\.zoneName) == [rig.populated.zone])
        #expect(rig.privateQueue.savedAgain == [sent.recordID])
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
