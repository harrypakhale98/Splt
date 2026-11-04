import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Sync status presentation")
struct UISyncStatusPresentationTests {
    @Test func noAccountExplainsHowToTurnOnICloud() {
        let text = SyncStatusPresentation.detail(for: .noAccount)
        #expect(text.contains("iCloud"))
        #expect(text.contains("Settings"))
    }

    @Test func unavailableBuildsSayDataStaysOnTheDevice() {
        #expect(SyncStatusPresentation.detail(for: .unavailable).contains("device"))
    }

    @Test func errorsShowTheirOwnMessage() {
        #expect(SyncStatusPresentation.detail(for: .error("Storage is full.")) == "Storage is full.")
    }

    @Test func everyStatusHasTitleDetailAndSymbol() {
        let all: [SyncStatus] = [.idle, .syncing, .offline, .noAccount, .restricted, .error("x"), .unavailable]
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

    @Test func inviteExplainsEveryStateItCannotWorkIn() {
        #expect(GroupInviteSection.note(for: .idle) == nil)
        #expect(GroupInviteSection.note(for: .syncing) == nil)
        for status in [SyncStatus.offline, .noAccount, .restricted, .error("Full"), .unavailable] {
            #expect(GroupInviteSection.note(for: status)?.contains("invite") == true || GroupInviteSection.note(for: status)?.contains("Inviting") == true)
            #expect(!status.isConnected)
        }
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
