import CloudKit
import Foundation
import SpltCore
import Testing
@testable import Splt

/// Account switches, failures that must clear, and work that must not be lost or repeated.
@MainActor
@Suite("Sync unhappy paths")
struct SyncUnhappyPathTests {
    @MainActor
    private struct Rig {
        let populated: PopulatedDevice
        let coordinator: SyncCoordinator
        let privateQueue = FakeQueue()
        let sharedQueue = FakeQueue()
        let delays = Recorder<TimeInterval>()
        let retryRuns = Recorder<Int>()

        var device: SyncDevice { populated.device }
        var people: any PersonRepository { populated.device.services.people }

        init(expenses: Bool) throws {
            populated = try PopulatedDevice()
            if expenses { try populated.addExpense() }
            let delays = self.delays
            let runs = self.retryRuns
            coordinator = SyncCoordinator(services: populated.device.services, adapter: populated.device.adapter)
            coordinator.setRetry(RetryScheduler(sleep: { delays.append($0) }, action: { runs.append(1) }))
            coordinator.attach(privateQueue, for: .privateDatabase)
            coordinator.attach(sharedQueue, for: .sharedDatabase)
        }
    }

    private let alice = CloudIdentity.personID(forUserRecordName: "_alice")
    private let bob = CloudIdentity.personID(forUserRecordName: "_bob")

    // MARK: Switching accounts

    @Test func anotherAccountGetsItsOwnProfileAndLeavesThePreviousOneInItsGroups() throws {
        let rig = try Rig(expenses: true)
        try rig.coordinator.begin(user: "_alice")
        try rig.coordinator.begin(user: "_bob")

        let me = try #require(try rig.people.me())
        #expect(me.id == bob)
        // nothing of the previous account's profile is carried over
        #expect(me.name == String(localized: "You"))
        #expect(try rig.people.person(id: alice)?.kind == .friend)
        #expect(try rig.people.person(id: alice)?.name == "Me")
        let group = try #require(try rig.device.services.groups.group(id: rig.populated.group.id))
        #expect(group.memberIDs.contains(alice))
        #expect(!group.memberIDs.contains(bob))
        #expect(try rig.device.tracker.pendingChanges().isEmpty)
        #expect(try rig.device.adapter.collectOutgoing().isEmpty)
    }

    @Test func theNewAccountsProfileFromTheServerReplacesTheStandIn() throws {
        let rig = try Rig(expenses: false)
        try rig.coordinator.begin(user: "_alice")
        try rig.coordinator.accountChanged(.switched(to: "_bob"))

        var fields = SyncFields()
        fields.set("name", "Bob")
        fields.set("kind", PersonKind.friend.rawValue)
        fields.set("claimedByCloudUserID", "_bob")
        let chosenLongAgo = rig.device.clock.start.addingTimeInterval(-10_000_000)
        let record = RecordMapper.record(
            for: SyncPayload(recordType: .person, recordName: bob.description, modifiedAt: chosenLongAgo, fields: fields),
            in: CKRecordZone.ID(zoneName: UUID().uuidString, ownerName: CKCurrentUserDefaultName)
        )
        let report = try rig.device.adapter.applyFetched(modifications: [record], deletions: [])
        #expect(report.requeue.isEmpty)
        #expect(try rig.people.me()?.id == bob)
        #expect(try rig.people.me()?.name == "Bob")
    }

    @Test func aSwitchToSomeoneWhoSharedAnExpenseWithThePreviousAccountStillChangesWhoYouAre() throws {
        let rig = try Rig(expenses: false)
        try rig.coordinator.begin(user: "_alice")
        let services = rig.device.services
        let group = rig.populated.group.id
        try services.people.add(Person(id: bob, name: "Bob", createdAt: rig.device.clock.start))
        try services.groups.addMember(bob, to: group)
        // merging these two people would have to add up their shares, which blocked the switch before
        try services.expenses.add(Expense(
            groupID: group, title: "Groceries", total: usdAmount(2000), date: rig.device.clock.start,
            paidBy: alice, split: .equal(participants: [alice, bob])
        ))

        try rig.coordinator.begin(user: "_bob")
        #expect(try rig.people.me()?.id == bob)
        #expect(try rig.people.me()?.name == "Bob")
        #expect(try rig.people.person(id: alice)?.kind == .friend)
        #expect(try services.expenses.expenses(in: group).count == 1)
    }

    @Test func aProfileLeftBehindByTheAccountBeforeIsHandedOverOnTheNextStart() throws {
        let rig = try Rig(expenses: false)
        try rig.coordinator.begin(user: "_alice")
        // what an earlier version left after a switch it could not finish
        rig.device.adapter.updateMetadata { $0.userRecordName = "_bob" }
        try rig.coordinator.begin(user: "_bob")
        #expect(try rig.people.me()?.id == bob)
        #expect(try rig.people.person(id: alice)?.kind == .friend)
    }

    @Test func bothEnginesReportingTheSwitchResetOnlyOnce() throws {
        let rig = try Rig(expenses: false)
        try rig.coordinator.begin(user: "_alice")
        try rig.coordinator.accountChanged(.switched(to: "_bob"))
        let bobsGroup = CKRecordZone.ID(zoneName: UUID().uuidString, ownerName: CKCurrentUserDefaultName)
        rig.device.adapter.registerZone(bobsGroup)

        try rig.coordinator.accountChanged(.switched(to: "_bob"))
        #expect(rig.device.adapter.metadata.isKnown(zoneName: bobsGroup.zoneName))
        #expect(!rig.device.adapter.metadata.isDetached(zoneName: bobsGroup.zoneName))
    }

    // MARK: Failures that clear

    @Test func aFetchThatGoesThroughStartsTheWaitingTimesOver() async throws {
        let rig = try Rig(expenses: false)
        for run in 1...2 {
            rig.coordinator.fetchFailed(CKError(.networkUnavailable), scope: .privateDatabase)
            #expect(await eventually { rig.retryRuns.count == run })
        }
        #expect(rig.coordinator.status == .offline)
        #expect(rig.delays.values == [15, 30])

        rig.coordinator.fetchSucceeded(scope: .privateDatabase)
        #expect(rig.coordinator.status == .idle)
        rig.coordinator.fetchFailed(CKError(.networkUnavailable), scope: .privateDatabase)
        #expect(await eventually { rig.retryRuns.count == 3 })
        #expect(rig.delays.values.last == 15)
    }

    @Test func aGroupYouWereRemovedFromIsNotResentAndTakesItsErrorAlong() throws {
        let rig = try Rig(expenses: true)
        let shared = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: "_owner")
        rig.device.adapter.registerZone(shared)
        rig.coordinator.markReady()
        let sent = try #require(try rig.device.outgoing().records.first)
        let before = rig.sharedQueue.plans.count

        try rig.coordinator.sentRecords(
            saved: [], failedSaves: [(sent, CKError(.permissionFailure))], deleted: [], failedDeletes: [:], scope: .sharedDatabase
        )
        // sent again at once, the same records would only be refused again
        #expect(rig.sharedQueue.plans.count == before)
        guard case .error = rig.coordinator.status else {
            Issue.record("expected an error status")
            return
        }

        try rig.coordinator.fetchedZones(modified: [], deleted: [(shared, .deleted)])
        #expect(rig.coordinator.status == .idle)
    }

    // MARK: Engines

    @Test func leavingBeforeTheAccountHasBeenCheckedIsRemembered() async {
        let store = InMemorySyncStateStore()
        let engine = AutomaticSyncEngine(
            environment: { .signedDevice() }, probe: FakeAccountProbe(.available), accountChanges: { AsyncStream { _ in } },
            stateStore: store, makeCloudKitEngine: { FakeSyncEngine(identifier: $0) }
        )
        #expect(engine.choice == nil)
        let group = GroupID()
        try? await engine.leave(group: group)
        #expect(store.loadMetadata().pendingLeaves == [group.description])
    }

    private func cloudKitEngine(
        connectivity: @escaping @Sendable () -> AsyncStream<Bool> = { AsyncStream { _ in } }
    ) throws -> (engine: CloudKitSyncEngine, backend: FakeCloudKitBackend) {
        let populated = try PopulatedDevice()
        let backend = FakeCloudKitBackend()
        backend.store = populated.device.store
        let engine = CloudKitSyncEngine(
            backend: backend, services: populated.device.services, store: populated.device.store,
            connectivity: connectivity, reconcileDelay: .milliseconds(10)
        )
        return (engine, backend)
    }

    @Test func comingBackOnlineFetchesAtOnce() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        let (engine, backend) = try cloudKitEngine(connectivity: { stream })
        await engine.start()
        #expect(await eventually { backend.privateHandle.fetchCount == 1 && backend.sharedHandle.fetchCount == 1 })
        continuation.yield(false)
        #expect(await eventually { engine.status == .offline })
        continuation.yield(true)
        #expect(await eventually { backend.privateHandle.fetchCount == 2 && backend.sharedHandle.fetchCount == 2 })
        await engine.stop()
        continuation.finish()
    }

    @Test func aDatabaseThatCannotBeFetchedDoesNotHoldUpTheOther() async throws {
        let (engine, backend) = try cloudKitEngine()
        backend.privateHandle.fetchError = CKError(.networkUnavailable)
        await engine.start()
        #expect(await eventually { backend.sharedHandle.fetchCount == 1 })
        await #expect(throws: CKError.self) { try await engine.fetchChanges() }
        #expect(backend.sharedHandle.fetchCount == 2)
        await engine.stop()
    }
}
