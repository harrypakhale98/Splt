import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Sync status presentation")
struct UISyncStatusPresentationTests {
    @Test func onlyAnErrorMarksTheAccountButton() {
        #expect(SyncStatusPresentation.needsAttention(.error("iCloud storage is full.")))
        for status: SyncStatus in [.idle, .syncing, .offline, .noAccount, .restricted, .unavailable(.simulator)] {
            #expect(!SyncStatusPresentation.needsAttention(status))
        }
    }

    @Test func noAccountExplainsHowToTurnOnICloud() {
        let text = SyncStatusPresentation.detail(for: .noAccount)
        #expect(text.contains("iCloud"))
        #expect(text.contains("Settings"))
    }

    @Test func eachReasonForBeingOffSaysWhyAndWhereTheDataIs() {
        let reasons: [SyncStatus.UnavailableReason] = [.simulator, .developerBuild, .notSetUp]
        let details = reasons.map { SyncStatusPresentation.detail(for: .unavailable($0)) }
        for detail in details {
            #expect(detail.contains("device"))
        }
        #expect(Set(details).count == reasons.count)
        #expect(SyncStatusPresentation.detail(for: .unavailable(.simulator)).contains("iPhone"))
    }

    @Test func eachReasonMapsToItsOwnStatus() {
        #expect(NoOpReason.simulator.status == .unavailable(.simulator))
        #expect(NoOpReason.testing.status == .unavailable(.developerBuild))
        #expect(NoOpReason.preview.status == .unavailable(.developerBuild))
        #expect(NoOpReason.missingEntitlement.status == .unavailable(.notSetUp))
    }

    @Test func errorsShowTheirOwnMessage() {
        #expect(SyncStatusPresentation.detail(for: .error("Storage is full.")) == "Storage is full.")
    }

    @Test func everyStatusHasTitleDetailAndSymbol() {
        let all: [SyncStatus] = [
            .idle, .syncing, .offline, .noAccount, .restricted, .error("x"),
            .unavailable(.starting), .unavailable(.simulator), .unavailable(.developerBuild), .unavailable(.notSetUp),
        ]
        for status in all {
            #expect(!status.title.isEmpty)
            #expect(!SyncStatusPresentation.detail(for: status).isEmpty)
            #expect(!status.symbolName.isEmpty)
        }
    }
}

@MainActor
@Suite("Group sharing through sync")
struct UISyncGroupSharingTests {
    private let group = GroupID()

    @Test func fallsBackToTheLocalLinkWhenSyncIsNotConnected() async throws {
        let engine = FakeSyncEngine()
        engine.report(.noAccount)
        let runtime = SyncRuntime()
        runtime.use(engine)

        let url = try await SyncGroupSharing(runtime: runtime).inviteURL(for: group, groupName: "Trip")
        #expect(url == DeepLink.group(group.rawValue).url)
    }

    @Test func fallsBackWhenTheEngineCannotShare() async throws {
        let runtime = SyncRuntime()
        runtime.use(FakeSyncEngine())

        let url = try await SyncGroupSharing(runtime: runtime).inviteURL(for: group, groupName: "Trip")
        #expect(url == DeepLink.group(group.rawValue).url)
    }

    @Test func aLinkToAGroupThisDeviceDoesNotHaveOpensNothingElse() {
        let router = Router()
        let id = UUID()
        #expect(router.open(URL(string: "splt://group/\(id.uuidString)")!))
        #expect(router.groupsPath == [.group(id)])
        #expect(router.sheet == nil)
        #expect(router.pendingInvite == nil)
    }

    @Test func leavingIsForwardedWhenConnected() async throws {
        let engine = FakeSyncEngine()
        let runtime = SyncRuntime()
        runtime.use(engine)

        try await SyncGroupSharing(runtime: runtime).leave(groupID: group)
        #expect(engine.left == [group])
    }

    @Test func leavingWhileOfflineStillReachesTheEngine() async throws {
        let engine = FakeSyncEngine()
        engine.report(.offline)
        let runtime = SyncRuntime()
        runtime.use(engine)

        try await SyncGroupSharing(runtime: runtime).leave(groupID: group)
        #expect(engine.left == [group])
    }

    @Test func leavingWithoutSyncIsFine() async throws {
        let runtime = SyncRuntime()
        runtime.use(NoOpSyncEngine(reason: .simulator))
        try await SyncGroupSharing(runtime: runtime).leave(groupID: group)
    }
}
