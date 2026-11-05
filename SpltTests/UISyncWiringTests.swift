import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Sync status presentation")
struct UISyncStatusPresentationTests {
    @Test func onlyAnErrorMarksTheAccountButton() {
        #expect(SyncStatusPresentation.needsAttention(.error("iCloud storage is full.")))
        for status: SyncStatus in [.idle, .syncing, .offline, .noAccount, .restricted, .unavailable] {
            #expect(!SyncStatusPresentation.needsAttention(status))
        }
    }

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

    @Test func leavingIsForwardedWhenConnected() async throws {
        let engine = FakeSyncEngine()
        let runtime = SyncRuntime()
        runtime.use(engine)

        try await SyncGroupSharing(runtime: runtime).leave(groupID: group)
        #expect(engine.left == [group])
    }

    @Test func leavingDoesNothingWhenNotConnected() async throws {
        let engine = FakeSyncEngine()
        engine.report(.unavailable)
        let runtime = SyncRuntime()
        runtime.use(engine)

        try await SyncGroupSharing(runtime: runtime).leave(groupID: group)
        #expect(engine.left.isEmpty)
    }
}
