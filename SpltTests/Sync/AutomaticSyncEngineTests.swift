import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Automatic sync engine")
struct AutomaticSyncEngineTests {
    private func make(
        environment: SyncEnvironment, account: AccountAvailability = .available,
        changes: AsyncStream<Void> = AsyncStream { _ in }, recheck: Duration = .seconds(30)
    ) -> (engine: AutomaticSyncEngine, probe: FakeAccountProbe, made: Made) {
        let probe = FakeAccountProbe(account)
        let made = Made()
        let engine = AutomaticSyncEngine(
            environment: { environment }, probe: probe, accountChanges: { changes }, recheckInterval: recheck,
            makeCloudKitEngine: { identifier in
                let fake = FakeSyncEngine(identifier: identifier)
                made.engines.append(fake)
                return fake
            }
        )
        return (engine, probe, made)
    }

    @MainActor
    final class Made {
        var engines: [FakeSyncEngine] = []
    }

    @Test func simulatorStaysOfflineAndNeverAsksCloudKit() async {
        var environment = SyncEnvironment.signedDevice()
        environment.isSimulator = true
        let (engine, probe, made) = make(environment: environment)
        await engine.start()
        #expect(engine.choice == .noOp(.simulator))
        #expect(engine.status == .unavailable)
        #expect(probe.requests.isEmpty)
        #expect(made.engines.isEmpty)
        await engine.stop()
    }

    @Test func missingEntitlementNeverAsksCloudKit() async {
        let (engine, probe, made) = make(environment: .signedDevice(entitlements: .none))
        await engine.start()
        #expect(engine.choice == .noOp(.missingEntitlement))
        #expect(probe.requests.isEmpty)
        #expect(made.engines.isEmpty)
        await engine.stop()
    }

    @Test func signedInDeviceStartsTheCloudKitEngine() async {
        let (engine, probe, made) = make(environment: .signedDevice())
        await engine.start()
        #expect(engine.choice == .cloudKit(containerIdentifier: "iCloud.com.example.app"))
        #expect(probe.requests == ["iCloud.com.example.app"])
        #expect(made.engines.count == 1)
        #expect(made.engines[0].startCount == 1)
        made.engines[0].report(.syncing)
        #expect(await eventually { engine.status == .syncing })
        await engine.stop()
        #expect(made.engines[0].stopCount == 1)
    }

    @Test func restrictedAccountReportsRestricted() async {
        let (engine, _, made) = make(environment: .signedDevice(), account: .restricted)
        await engine.start()
        #expect(engine.status == .restricted)
        #expect(made.engines.isEmpty)
        await engine.stop()
    }

    @Test func switchesEnginesWhenTheAccountAppears() async {
        let (engine, probe, made) = make(environment: .signedDevice(), account: .noAccount)
        await engine.start()
        #expect(engine.status == .noAccount)
        probe.set(.available)
        await engine.reevaluate()
        #expect(engine.choice == .cloudKit(containerIdentifier: "iCloud.com.example.app"))
        #expect(made.engines.count == 1)
        probe.set(.noAccount)
        await engine.reevaluate()
        #expect(engine.status == .noAccount)
        #expect(made.engines[0].stopCount == 1)
        await engine.stop()
    }

    @Test func reevaluatingWithTheSameAnswerKeepsTheEngine() async {
        let (engine, _, made) = make(environment: .signedDevice())
        await engine.start()
        await engine.reevaluate()
        #expect(made.engines.count == 1)
        #expect(made.engines[0].startCount == 1)
        await engine.stop()
    }

    @Test func accountChangeNotificationsTriggerAReevaluation() async {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let (engine, probe, made) = make(environment: .signedDevice(), account: .noAccount, changes: stream)
        await engine.start()
        probe.set(.available)
        continuation.yield()
        #expect(await eventually { made.engines.count == 1 })
        continuation.finish()
        await engine.stop()
    }

    @Test func anUnreachableAccountIsCheckedAgainLater() async {
        let (engine, probe, made) = make(environment: .signedDevice(), account: .unknown, recheck: .milliseconds(20))
        await engine.start()
        #expect(engine.status == .offline)
        probe.set(.available)
        #expect(await eventually { made.engines.count == 1 })
        #expect(engine.choice == .cloudKit(containerIdentifier: "iCloud.com.example.app"))
        await engine.stop()
    }

    @Test func requestsAreForwardedToTheCurrentEngine() async throws {
        let (engine, _, made) = make(environment: .signedDevice())
        await engine.start()
        try await engine.sendChanges()
        try await engine.fetchChanges()
        try await engine.accept(ShareInvitation(groupName: "Lisbon"))
        let group = GroupID()
        try await engine.leave(group: group)
        let fake = made.engines[0]
        #expect(fake.sendCount == 1)
        #expect(fake.fetchCount == 1)
        #expect(fake.accepted.count == 1)
        #expect(fake.left == [group])
        await engine.stop()
    }
}

@MainActor
@Suite("No-op sync engine")
struct NoOpSyncEngineTests {
    @Test func startsQuietlyAndRefusesSharing() async {
        let engine = NoOpSyncEngine(reason: .simulator)
        await engine.start()
        #expect(engine.status == .unavailable)
        await #expect(throws: SyncError.unavailable) { try await engine.share(group: GroupID()) }
        await #expect(throws: SyncError.unavailable) { try await engine.accept(ShareInvitation(groupName: nil)) }
        await #expect(throws: SyncError.unavailable) { try await engine.leave(group: GroupID()) }
        try? await engine.sendChanges()
        try? await engine.fetchChanges()
        await engine.stop()
    }

    @Test func statusStreamStartsWithTheCurrentStatus() async {
        let engine = NoOpSyncEngine(reason: .noAccount)
        var iterator = engine.statusUpdates.makeAsyncIterator()
        #expect(await iterator.next() == .noAccount)
    }
}

@MainActor
@Suite("Status broadcaster")
struct StatusBroadcasterTests {
    @Test func listenersSeeCurrentThenChanges() async {
        let broadcaster = StatusBroadcaster(initial: .idle)
        var first = broadcaster.updates().makeAsyncIterator()
        var second = broadcaster.updates().makeAsyncIterator()
        #expect(await first.next() == .idle)
        #expect(broadcaster.send(.syncing))
        #expect(await first.next() == .syncing)
        #expect(await second.next() == .syncing)
    }

    @Test func repeatedStatusIsNotSentTwice() {
        let broadcaster = StatusBroadcaster(initial: .idle)
        #expect(!broadcaster.send(.idle))
        #expect(broadcaster.send(.offline))
        #expect(!broadcaster.send(.offline))
    }
}

@Suite("Sync status")
struct SyncStatusTests {
    @Test func everyStatusHasFriendlyText() {
        let all: [SyncStatus] = [.idle, .syncing, .offline, .noAccount, .restricted, .error("Storage is full."), .unavailable]
        for status in all {
            #expect(!status.title.isEmpty)
            #expect(!status.detail.isEmpty)
            #expect(!status.symbolName.isEmpty)
        }
        #expect(SyncStatus.error("Storage is full.").detail == "Storage is full.")
    }

    @Test func onlyIdleAndSyncingCountAsConnected() {
        #expect(SyncStatus.idle.isConnected)
        #expect(SyncStatus.syncing.isConnected)
        #expect(!SyncStatus.offline.isConnected)
        #expect(!SyncStatus.unavailable.isConnected)
    }
}
