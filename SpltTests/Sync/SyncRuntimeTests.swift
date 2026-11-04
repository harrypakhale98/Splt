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
        #expect(runtime.status == .unavailable)
        await #expect(throws: SyncError.unavailable) {
            _ = try await runtime.engine.share(group: .init())
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

    @Test func aReplacementEngineIsUsedForPreviews() {
        let runtime = SyncRuntime()
        let fake = FakeSyncEngine()
        fake.report(.syncing)
        runtime.use(fake)
        #expect(runtime.status == .syncing)
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

    @Test func leavingForwardsToTheEngine() async {
        let engine = FakeSyncEngine()
        let model = GroupSharingModel(engine: engine)
        let group = GroupID()
        await model.leave(group: group)
        #expect(engine.left == [group])
        #expect(model.phase == .idle)
    }
}
