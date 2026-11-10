import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Sync runtime")
struct SyncRuntimeTests {
    @Test func testsRunOfflineAndReportThatSyncIsUnavailable() async throws {
        let runtime = SyncRuntime()
        let services = try DataServices.inMemory()
        await runtime.start(services: services)
        #expect(runtime.status == .unavailable(.developerBuild))
        await #expect(throws: SyncError.unavailable) {
            _ = try await runtime.engine.share(group: .init(), anyoneWithLink: false)
        }
    }

    @Test func invitationsThatArriveBeforeStartAreAnsweredAfterStart() async throws {
        let runtime = SyncRuntime()
        var failures: [String] = []
        runtime.onInvitationFailed = { failures.append($0) }
        runtime.receive(ShareInvitation(groupName: "Lisbon"))
        #expect(failures.isEmpty)
        await runtime.start(services: try DataServices.inMemory())
        #expect(failures == ["iCloud sync is not available in this build."])
    }

    @Test func invitationsAfterStartAreAnsweredToo() async throws {
        let runtime = SyncRuntime()
        var failures: [String] = []
        runtime.onInvitationFailed = { failures.append($0) }
        await runtime.start(services: try DataServices.inMemory())
        runtime.receive(ShareInvitation(groupName: nil))
        #expect(await eventually { failures.count == 1 })
    }

    @Test func anInvitationAtAColdLaunchWaitsUntilSyncHasStarted() async throws {
        let fake = FakeSyncEngine()
        fake.acceptError = SyncError.notReady
        let runtime = SyncRuntime(invitationRetry: .milliseconds(10), makeEngine: { _ in fake })
        var failures: [String] = []
        runtime.onInvitationFailed = { failures.append($0) }
        runtime.receive(ShareInvitation(groupName: "Lisbon"))
        await runtime.start(services: try DataServices.inMemory())
        try await Task.sleep(for: .milliseconds(50))
        #expect(failures.isEmpty)
        #expect(fake.accepted.isEmpty)

        fake.acceptError = nil
        #expect(await eventually { fake.accepted.count == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(fake.accepted.count == 1)
        #expect(failures.isEmpty)
    }

    @Test func anInvitationWaitsWhileICloudCannotBeReachedAndIsAnsweredOnceItCan() async throws {
        let probe = FakeAccountProbe(.unknown)
        let cloudKit = FakeSyncEngine()
        let automatic = AutomaticSyncEngine(
            environment: { .signedDevice() }, probe: probe, accountChanges: { AsyncStream { _ in } },
            stateStore: InMemorySyncStateStore(), makeCloudKitEngine: { _ in cloudKit }
        )
        let runtime = SyncRuntime(invitationRetry: .milliseconds(10), makeEngine: { _ in automatic })
        var failures: [String] = []
        runtime.onInvitationFailed = { failures.append($0) }
        runtime.receive(ShareInvitation(groupName: "Lisbon"))
        await runtime.start(services: try DataServices.inMemory())
        try await Task.sleep(for: .milliseconds(50))
        #expect(failures.isEmpty)

        probe.set(.available)
        await automatic.reevaluate()
        #expect(await eventually { cloudKit.accepted.count == 1 })
        #expect(failures.isEmpty)
        await automatic.stop()
    }

    @Test func anInvitationFailsAtOnceWhenNobodyIsSignedInToICloud() async throws {
        let automatic = AutomaticSyncEngine(
            environment: { .signedDevice() }, probe: FakeAccountProbe(.noAccount), accountChanges: { AsyncStream { _ in } },
            stateStore: InMemorySyncStateStore(), makeCloudKitEngine: { FakeSyncEngine(identifier: $0) }
        )
        let runtime = SyncRuntime(makeEngine: { _ in automatic })
        var failures: [String] = []
        runtime.onInvitationFailed = { failures.append($0) }
        runtime.receive(ShareInvitation(groupName: "Lisbon"))
        await runtime.start(services: try DataServices.inMemory())
        #expect(failures == ["Sign in to iCloud in the Settings app, then open the invitation again."])
        await automatic.stop()
    }

    @Test func aReplacementEngineIsUsedForPreviews() {
        let runtime = SyncRuntime()
        let fake = FakeSyncEngine()
        fake.report(.syncing)
        runtime.use(fake)
        #expect(runtime.status == .syncing)
    }

    @Test func joiningAGroupYouLeftBringsItBackToYourList() {
        let left = isolatedLeftGroups()
        let group = GroupID()
        left.insert(group)
        let runtime = SyncRuntime(leftGroups: left)
        var opened: [GroupID] = []
        runtime.onGroupJoined = { opened.append($0) }
        runtime.groupJoined(group)
        #expect(!left.contains(group))
        #expect(opened == [group])
    }

    @Test func aPushThatLaunchedTheAppStartsSync() async throws {
        let services = try DataServices.inMemory()
        var asked = 0
        let runtime = SyncRuntime(liveServices: {
            asked += 1
            return services
        })
        let push: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "ck": ["ce": 2, "cid": "iCloud.com.example.app", "nid": UUID().uuidString, "fet": ["zid": "zone", "dbs": 1, "zoid": "_owner", "sid": "sub"]],
        ]
        #expect(await runtime.handleRemoteNotification(push))
        #expect(asked == 1)
        #expect(runtime.engine is AutomaticSyncEngine)
        #expect(await runtime.handleRemoteNotification(push))
        #expect(asked == 1)
    }

    @Test func pushesThatAreNotFromCloudKitAreIgnored() async {
        let runtime = SyncRuntime()
        #expect(await runtime.handleRemoteNotification(["aps": ["alert": "hello"]]) == false)
        #expect(await runtime.handleRemoteNotification([:]) == false)
    }
}

@MainActor
@Suite("Group sharing model")
struct GroupSharingModelTests {
    @Test func failuresBecomeFriendlyMessages() async {
        let model = GroupSharingModel(engine: NoOpSyncEngine(reason: .simulator))
        await model.prepare(group: GroupID())
        #expect(model.phase == .failed("iCloud sync is not available in this build."))
        #expect(model.prepared == nil)
        model.dismissError()
        #expect(model.phase == .idle)
    }
}
