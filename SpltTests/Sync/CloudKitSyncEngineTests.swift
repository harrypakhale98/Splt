import CloudKit
import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("CloudKit sync engine")
struct CloudKitSyncEngineTests {
    @MainActor
    private struct Rig {
        let populated: PopulatedDevice
        let backend = FakeCloudKitBackend()
        let engine: CloudKitSyncEngine

        var device: SyncDevice { populated.device }

        init(seed: (SyncMetadata) -> SyncMetadata = { $0 }) throws {
            populated = try PopulatedDevice()
            populated.device.store.saveMetadata(seed(populated.device.store.loadMetadata()))
            engine = CloudKitSyncEngine(
                backend: backend, services: populated.device.services, store: populated.device.store,
                connectivity: { AsyncStream { _ in } }, reconcileDelay: .milliseconds(10)
            )
        }
    }

    @Test func aSignedOutAccountShowsNoAccountAndStartsNoEngines() async throws {
        let rig = try Rig()
        rig.backend.userResult = .failure(CKError(.notAuthenticated))
        await rig.engine.start()
        #expect(rig.engine.status == .noAccount)
        #expect(rig.engine.syncers.isEmpty)
        #expect(rig.backend.madeEngines.isEmpty)
    }

    @Test func startingCreatesAnEnginePerDatabaseAndFetchesFirst() async throws {
        let rig = try Rig()
        await rig.engine.start()
        #expect(rig.backend.madeEngines == [.privateDatabase, .sharedDatabase])
        #expect(await eventually { rig.backend.privateHandle.fetchCount == 1 && rig.backend.sharedHandle.fetchCount == 1 })
        #expect(try rig.device.services.people.me()?.id == CloudIdentity.personID(forUserRecordName: "_alice"))
        await rig.engine.stop()
    }

    @Test func localDataIsQueuedOnceTheFirstFetchIsDone() async throws {
        let rig = try Rig()
        try rig.populated.addExpense()
        await rig.engine.start()
        let zone = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: CKCurrentUserDefaultName)
        #expect(await eventually { !rig.backend.privateHandle.savedRecordIDs.isEmpty })
        #expect(rig.backend.privateHandle.savedZoneIDs == [zone])
        #expect(rig.backend.privateHandle.savedRecordIDs.allSatisfy { $0.zoneID == zone })
        #expect(rig.backend.sharedHandle.recordChanges.isEmpty)
        await rig.engine.stop()
    }

    @Test func aFailedFirstFetchStillQueuesLocalChangesAndShowsOffline() async throws {
        let rig = try Rig()
        rig.backend.privateHandle.fetchError = CKError(.networkUnavailable)
        try rig.populated.addExpense()
        await rig.engine.start()
        #expect(await eventually { !rig.backend.privateHandle.savedRecordIDs.isEmpty })
        #expect(rig.engine.status == .offline)
        await rig.engine.stop()
    }

    @Test func laterEditsAreQueuedAfterAShortDelay() async throws {
        let rig = try Rig()
        await rig.engine.start()
        #expect(await eventually { rig.backend.privateHandle.fetchCount == 1 })
        _ = await eventually { !rig.backend.privateHandle.savedRecordIDs.isEmpty }
        let before = rig.backend.privateHandle.savedRecordIDs.count
        let expense = try rig.populated.addExpense("Late edit")
        #expect(await eventually { rig.backend.privateHandle.savedRecordIDs.contains { $0.recordName == expense.id.description } })
        #expect(rig.backend.privateHandle.savedRecordIDs.count > before)
        await rig.engine.stop()
    }

    @Test func sendingAndFetchingNowGoToBothDatabases() async throws {
        let rig = try Rig()
        await rig.engine.start()
        #expect(await eventually { rig.backend.sharedHandle.fetchCount == 1 })
        try await rig.engine.sendChanges()
        try await rig.engine.fetchChanges()
        #expect(rig.backend.privateHandle.sendCount == 1 && rig.backend.sharedHandle.sendCount == 1)
        #expect(rig.backend.privateHandle.fetchCount == 2 && rig.backend.sharedHandle.fetchCount == 2)
        await rig.engine.stop()
    }

    @Test func engineEventsMoveTheStatus() async throws {
        let rig = try Rig()
        await rig.engine.start()
        #expect(await eventually { rig.backend.sharedHandle.fetchCount == 1 })
        let syncer = try #require(rig.engine.syncers.first)
        syncer.handle(.operationStarted)
        #expect(rig.engine.status == .syncing)
        syncer.handle(.operationEnded)
        #expect(rig.engine.status == .idle)
        var updates = rig.engine.statusUpdates.makeAsyncIterator()
        #expect(await updates.next() == .idle)
        await rig.engine.stop()
    }

    @Test func stoppingCancelsBothEnginesAndAllowsARestart() async throws {
        let rig = try Rig()
        await rig.engine.start()
        await rig.engine.stop()
        #expect(rig.backend.privateHandle.cancelCount == 1 && rig.backend.sharedHandle.cancelCount == 1)
        #expect(rig.engine.syncers.isEmpty)
        await rig.engine.start()
        #expect(rig.backend.madeEngines.count == 4)
        await rig.engine.stop()
    }

    // MARK: Leaving

    @Test func leavingASharedGroupHidesItAndLeavesTheZone() async throws {
        let owner = "_owner"
        let rig = try Rig()
        let zoneName = rig.populated.zone
        rig.device.store.saveMetadata({
            var metadata = rig.device.store.loadMetadata()
            metadata.zones[zoneName] = ZoneInfo(ownerName: owner, scope: .sharedDatabase)
            return metadata
        }())
        let engine = CloudKitSyncEngine(
            backend: rig.backend, services: rig.device.services, store: rig.device.store,
            connectivity: { AsyncStream { _ in } }, reconcileDelay: .milliseconds(10)
        )
        await engine.start()
        try await engine.leave(group: rig.populated.group.id)
        let zone = CKRecordZone.ID(zoneName: zoneName, ownerName: owner)
        #expect(rig.backend.sharedHandle.deletedZoneIDs == [zone])
        #expect(rig.backend.sharedHandle.sendCount == 1)
        #expect(try rig.device.services.groups.group(id: rig.populated.group.id) == nil)
        await engine.stop()
    }

    @Test func theOwnerLeavingStopsSharingAndKeepsTheGroup() async throws {
        let rig = try Rig()
        await rig.engine.start()
        let zone = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: CKCurrentUserDefaultName)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        rig.backend.privateDatabase.put(CKShare(recordZoneID: zone))
        try await rig.engine.leave(group: rig.populated.group.id)
        #expect(!rig.backend.privateDatabase.contains(shareID))
        #expect(try rig.device.services.groups.group(id: rig.populated.group.id) != nil)
        await #expect(throws: SyncError.notShared) { try await rig.engine.leave(group: rig.populated.group.id) }
        await rig.engine.stop()
    }

    @Test func leavingAnUnknownGroupFails() async throws {
        let rig = try Rig()
        await rig.engine.start()
        await #expect(throws: SyncError.groupNotFound) { try await rig.engine.leave(group: GroupID()) }
        await rig.engine.stop()
    }

    // MARK: Sharing and invitations

    @Test func sharingBeforeStartIsNotReady() async throws {
        let rig = try Rig()
        await #expect(throws: SyncError.notReady) { _ = try await rig.engine.share(group: rig.populated.group.id) }
        await #expect(throws: SyncError.groupNotFound) { _ = try await rig.engine.share(group: GroupID()) }
    }

    @Test func sharingSendsTheZoneFirstThenSavesAZoneWideShare() async throws {
        let rig = try Rig()
        await rig.engine.start()
        #expect(await eventually { rig.backend.privateHandle.fetchCount == 1 })
        await #expect(throws: FakeBackendError.noContainer) { _ = try await rig.engine.share(group: rig.populated.group.id) }
        #expect(rig.backend.privateHandle.sendCount >= 1)
        let zone = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: CKCurrentUserDefaultName)
        #expect(rig.backend.privateDatabase.contains(CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)))
        await rig.engine.stop()
    }

    @Test func invitationsWithoutMetadataAreRejected() async throws {
        let rig = try Rig()
        await rig.engine.start()
        await #expect(throws: SyncError.invalidInvitation) { try await rig.engine.accept(ShareInvitation(groupName: "x")) }
        await rig.engine.stop()
    }
}
