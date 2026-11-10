import CloudKit
import Foundation
import SpltCore
import SwiftData
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

    @Test func leavingAGroupInYourOwnICloudChangesNothingOnTheServer() async throws {
        let rig = try Rig()
        await rig.engine.start()
        let zone = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: CKCurrentUserDefaultName)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        rig.backend.privateDatabase.put(CKShare(recordZoneID: zone))
        try await rig.engine.leave(group: rig.populated.group.id)
        #expect(rig.backend.privateDatabase.contains(shareID))
        #expect(rig.backend.sharedHandle.deletedZoneIDs.isEmpty)
        await rig.engine.stop()
    }

    @Test func theOwnerOfASharedGroupIsToldSoAndTheAnswerLastsOffline() async throws {
        let rig = try Rig()
        await rig.engine.start()
        let group = rig.populated.group.id
        #expect(await !rig.engine.isSharedByMe(group: group))
        let zone = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: CKCurrentUserDefaultName)
        rig.backend.privateDatabase.put(CKShare(recordZoneID: zone))
        #expect(await rig.engine.isSharedByMe(group: group))
        rig.backend.privateDatabase.fetchError = CKError(.networkUnavailable)
        #expect(await rig.engine.isSharedByMe(group: group))
        await rig.engine.stop()
    }

    @Test func aGroupSomeoneElseSharedIsNotSharedByMe() async throws {
        let (rig, engine, _) = try sharedRig()
        await engine.start()
        #expect(await !engine.isSharedByMe(group: rig.populated.group.id))
        await engine.stop()
    }

    @Test func onlyGroupsOthersSharedAreSharedWithMe() throws {
        let own = try Rig()
        #expect(own.engine.groupsSharedWithMe.isEmpty)
        let (rig, engine, _) = try sharedRig()
        #expect(engine.groupsSharedWithMe == [rig.populated.group.id])
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
        await #expect(throws: SyncError.notReady) { _ = try await rig.engine.share(group: rig.populated.group.id, anyoneWithLink: false) }
        await #expect(throws: SyncError.groupNotFound) { _ = try await rig.engine.share(group: GroupID(), anyoneWithLink: false) }
    }

    @Test func sharingSendsTheZoneFirstThenSavesAZoneWideShare() async throws {
        let rig = try Rig()
        await rig.engine.start()
        #expect(await eventually { rig.backend.privateHandle.fetchCount == 1 })
        await #expect(throws: FakeBackendError.noContainer) { _ = try await rig.engine.share(group: rig.populated.group.id, anyoneWithLink: false) }
        #expect(rig.backend.privateHandle.sendCount >= 1)
        let zone = CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: CKCurrentUserDefaultName)
        #expect(rig.backend.privateDatabase.contains(CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)))
        await rig.engine.stop()
    }

    @Test func aGroupLeftOverFromAnotherAccountCannotBeSharedAndSaysWhy() async throws {
        let rig = try Rig(seed: {
            var metadata = $0
            metadata.userRecordName = "_previous"
            return metadata
        })
        await rig.engine.start()
        #expect(rig.device.store.loadMetadata().isDetached(zoneName: rig.populated.zone))
        await #expect(throws: SyncError.notInThisAccount) {
            _ = try await rig.engine.share(group: rig.populated.group.id, anyoneWithLink: false)
        }
        #expect(rig.backend.privateDatabase.saveCount == 0)
        await rig.engine.stop()
    }

    @Test func someoneWhoJoinedIsNotGivenTheSystemInviteSheet() async throws {
        let (rig, engine, zone) = try sharedRig()
        let share = CKShare(recordZoneID: zone)
        share.publicPermission = .readWrite
        rig.backend.sharedDatabase.put(share)
        await engine.start()
        let group = rig.populated.group.id
        await #expect(throws: SyncError.ownerInvites) { _ = try await engine.share(group: group, anyoneWithLink: false) }
        // the link of a share that is open to anyone is still theirs to pass on
        await #expect(throws: FakeBackendError.noContainer) { _ = try await engine.share(group: group, anyoneWithLink: true) }
        await engine.stop()
    }

    @Test func anInvitationBeforeSyncHasStartedHasToWait() async throws {
        let rig = try Rig()
        await #expect(throws: SyncError.notReady) { try await rig.engine.accept(ShareInvitation(groupName: "x")) }
        rig.backend.userResult = .failure(CKError(.networkUnavailable))
        await rig.engine.start()
        await #expect(throws: SyncError.notReady) { try await rig.engine.accept(ShareInvitation(groupName: "x")) }
        await rig.engine.stop()
    }

    @Test func onlyAShareLimitedToInvitedPeopleIsInviteOnly() async throws {
        let rig = try Rig()
        let group = rig.populated.group.id
        await rig.engine.start()
        #expect(await eventually { rig.backend.privateHandle.fetchCount == 1 })
        #expect(try await !rig.engine.isSharedInviteOnly(group: group))
        await #expect(throws: FakeBackendError.noContainer) { _ = try await rig.engine.share(group: group, anyoneWithLink: false) }
        #expect(try await rig.engine.isSharedInviteOnly(group: group))
        await #expect(throws: FakeBackendError.noContainer) { _ = try await rig.engine.share(group: group, anyoneWithLink: true) }
        #expect(try await !rig.engine.isSharedInviteOnly(group: group))
        await rig.engine.stop()
    }

    @Test func aGroupSomeoneElseSharedIsNeverInviteOnlyForYou() async throws {
        let (rig, engine, _) = try sharedRig()
        await engine.start()
        #expect(try await !engine.isSharedInviteOnly(group: rig.populated.group.id))
        await engine.stop()
    }

    @Test func invitationsWithoutMetadataAreRejected() async throws {
        let rig = try Rig()
        await rig.engine.start()
        await #expect(throws: SyncError.invalidInvitation) { try await rig.engine.accept(ShareInvitation(groupName: "x")) }
        await rig.engine.stop()
    }

    @Test func aFailedStartTriesAgainUntilItWorks() async throws {
        let rig = try Rig()
        rig.backend.userResult = .failure(CKError(.networkUnavailable))
        let engine = CloudKitSyncEngine(
            backend: rig.backend, services: rig.device.services, store: rig.device.store,
            connectivity: { AsyncStream { _ in } }, reconcileDelay: .milliseconds(10),
            retryPolicy: BackoffPolicy(base: 0.01, cap: 0.01)
        )
        await engine.start()
        #expect(engine.status == .offline)
        #expect(rig.backend.madeEngines.isEmpty)
        rig.backend.userResult = .success("_alice")
        #expect(await eventually { rig.backend.madeEngines.count == 2 })
        #expect(await eventually { engine.status != .offline })
        await engine.stop()
    }

    @Test func stoppingEndsTheAttemptsToStart() async throws {
        let rig = try Rig()
        rig.backend.userResult = .failure(CKError(.networkUnavailable))
        let engine = CloudKitSyncEngine(
            backend: rig.backend, services: rig.device.services, store: rig.device.store,
            connectivity: { AsyncStream { _ in } }, reconcileDelay: .milliseconds(10),
            retryPolicy: BackoffPolicy(base: 0.05, cap: 0.05)
        )
        await engine.start()
        await engine.stop()
        rig.backend.userResult = .success("_alice")
        try await Task.sleep(for: .milliseconds(200))
        #expect(rig.backend.madeEngines.isEmpty)
    }

    /// A group someone else shared with this device, on an engine that has not started yet.
    private func sharedRig(retry: BackoffPolicy = BackoffPolicy()) throws -> (rig: Rig, engine: CloudKitSyncEngine, zone: CKRecordZone.ID) {
        let rig = try Rig()
        var metadata = rig.device.store.loadMetadata()
        metadata.zones[rig.populated.zone] = ZoneInfo(ownerName: "_owner", scope: .sharedDatabase)
        rig.device.store.saveMetadata(metadata)
        let engine = CloudKitSyncEngine(
            backend: rig.backend, services: rig.device.services, store: rig.device.store,
            connectivity: { AsyncStream { _ in } }, reconcileDelay: .milliseconds(10), retryPolicy: retry
        )
        return (rig, engine, CKRecordZone.ID(zoneName: rig.populated.zone, ownerName: "_owner"))
    }

    /// Tells the engine the server accepted everything the group's zone has waiting.
    private func confirmUploads(_ rig: Rig, _ engine: CloudKitSyncEngine, zone: CKRecordZone.ID) throws {
        let tracker = rig.device.tracker
        let records = try tracker.pendingChanges().filter { $0.zoneName == zone.zoneName }.compactMap { change -> CKRecord? in
            try tracker.payload(recordType: change.recordType, recordName: change.recordName).map {
                RecordMapper.record(for: $0, in: zone)
            }
        }
        let syncer = try #require(engine.syncers.first { $0.scope == .sharedDatabase })
        syncer.handle(.sentRecords(saved: records, failedSaves: [], deleted: [], failedDeletes: [:]))
    }

    private func leaveThroughTheScreen(_ rig: Rig, _ engine: CloudKitSyncEngine) async -> (left: Bool, error: String?) {
        let runtime = SyncRuntime()
        runtime.use(engine)
        let model = GroupSettingsViewModel(groupID: rig.populated.group.id, services: rig.device.services, leftGroups: isolatedLeftGroups())
        let left = await model.leave(using: SyncGroupSharing(runtime: runtime))
        return (left, model.errorMessage)
    }

    private func removalNote(_ rig: Rig) throws -> ActivityRecord? {
        try rig.device.tracker.context.fetch(FetchDescriptor<ActivityRecord>()).first { $0.kindRaw == "memberRemoved" }
    }

    @Test func changesInASharedGroupYouAreInAreReportedAsMembership() async throws {
        let (rig, engine, zone) = try sharedRig()
        var groups: [GroupID] = []
        engine.onMembership = { groups.append($0) }
        await engine.start()
        let payload = try #require(try rig.device.tracker.payload(recordType: .group, recordName: zone.zoneName))
        let syncer = try #require(engine.syncers.first { $0.scope == .sharedDatabase })
        syncer.handle(.fetchedRecords(modifications: [RecordMapper.record(for: payload, in: zone)], deletions: []))
        #expect(groups == [rig.populated.group.id])
        await engine.stop()
    }

    @Test func leavingGivesUpTheZoneOnlyAfterTheRemovalWasSent() async throws {
        let (rig, engine, zone) = try sharedRig()
        await engine.start()
        #expect(await eventually { !rig.backend.sharedHandle.savedRecordIDs.isEmpty })
        let result = await leaveThroughTheScreen(rig, engine)
        #expect(result.left)
        #expect(result.error == nil)
        let note = try #require(try removalNote(rig))
        #expect(rig.backend.sharedHandle.savedRecordIDs.contains { $0.recordName == note.recordName })
        #expect(rig.backend.sharedHandle.deletedZoneIDs.isEmpty)
        #expect(try rig.device.services.groups.group(id: rig.populated.group.id) != nil)

        try confirmUploads(rig, engine, zone: zone)
        #expect(rig.backend.sharedHandle.deletedZoneIDs == [zone])
        #expect(try rig.device.services.groups.group(id: rig.populated.group.id) == nil)
        await engine.stop()
    }

    @Test func leavingWhileOfflineKeepsTheRemovalAndFinishesWhenItIsSent() async throws {
        let (rig, engine, zone) = try sharedRig()
        await engine.start()
        #expect(await eventually { !rig.backend.sharedHandle.savedRecordIDs.isEmpty })
        rig.backend.sharedHandle.sendError = CKError(.networkUnavailable)
        let result = await leaveThroughTheScreen(rig, engine)
        #expect(result.left)
        let note = try #require(try removalNote(rig))
        #expect(note.isDirty)
        #expect(note.deletedAt == nil)
        #expect(rig.backend.sharedHandle.deletedZoneIDs.isEmpty)
        #expect(rig.device.store.loadMetadata().pendingLeaves == [zone.zoneName])

        rig.backend.sharedHandle.sendError = nil
        try confirmUploads(rig, engine, zone: zone)
        #expect(rig.backend.sharedHandle.deletedZoneIDs == [zone])
        #expect(rig.device.store.loadMetadata().pendingLeaves?.isEmpty == true)
        await engine.stop()
    }

    @Test func leavingAfterAnOfflineLaunchIsRememberedAndFinishesOnceSyncStarts() async throws {
        let (rig, engine, zone) = try sharedRig(retry: BackoffPolicy(base: 0.01, cap: 0.01))
        rig.backend.userResult = .failure(CKError(.networkUnavailable))
        await engine.start()
        let result = await leaveThroughTheScreen(rig, engine)
        #expect(result.left)
        #expect(result.error == nil)
        #expect(rig.device.store.loadMetadata().pendingLeaves == [zone.zoneName])

        rig.backend.userResult = .success("_alice")
        #expect(await eventually { engine.syncers.count == 2 })
        let note = try #require(try removalNote(rig))
        #expect(await eventually { rig.backend.sharedHandle.savedRecordIDs.contains { $0.recordName == note.recordName } })
        #expect(rig.backend.sharedHandle.deletedZoneIDs.isEmpty)
        try confirmUploads(rig, engine, zone: zone)
        #expect(rig.backend.sharedHandle.deletedZoneIDs == [zone])
        await engine.stop()
    }

    @Test func aLeaveWaitingToFinishSurvivesARelaunch() async throws {
        let (rig, engine, zone) = try sharedRig()
        await engine.start()
        #expect(await eventually { !rig.backend.sharedHandle.savedRecordIDs.isEmpty })
        rig.backend.sharedHandle.sendError = CKError(.networkUnavailable)
        _ = await leaveThroughTheScreen(rig, engine)
        await engine.stop()
        rig.backend.sharedHandle.sendError = nil

        let relaunched = CloudKitSyncEngine(
            backend: rig.backend, services: rig.device.services, store: rig.device.store,
            connectivity: { AsyncStream { _ in } }, reconcileDelay: .milliseconds(10)
        )
        await relaunched.start()
        #expect(await eventually { relaunched.syncers.count == 2 })
        try await Task.sleep(for: .milliseconds(50))
        try confirmUploads(rig, relaunched, zone: zone)
        #expect(rig.backend.sharedHandle.deletedZoneIDs == [zone])
        // given up here but not yet confirmed: planned again until the server says so
        #expect(try rig.device.tracker.pendingChanges().contains { $0.recordType == .group && $0.operation == .delete })
        await relaunched.stop()
    }

    @Test func aLeaveDoesNotWaitForAZoneThatRefusesTheChanges() async throws {
        let (rig, engine, zone) = try sharedRig()
        await engine.start()
        #expect(await eventually { !rig.backend.sharedHandle.savedRecordIDs.isEmpty })
        _ = await leaveThroughTheScreen(rig, engine)
        let note = try #require(try removalNote(rig))
        let payload = try #require(try rig.device.tracker.payload(recordType: .activity, recordName: note.recordName))
        let syncer = try #require(engine.syncers.first { $0.scope == .sharedDatabase })
        syncer.handle(.sentRecords(
            saved: [], failedSaves: [(RecordMapper.record(for: payload, in: zone), CKError(.permissionFailure))],
            deleted: [], failedDeletes: [:]
        ))
        #expect(rig.backend.sharedHandle.deletedZoneIDs == [zone])
        await engine.stop()
    }
}
