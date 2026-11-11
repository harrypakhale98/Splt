import CloudKit
import Foundation
import SpltCore
import Testing
@testable import Splt

/// Anyone in a shared group can write a claim record for anyone. A claim only counts for the
/// person who wrote it, so nobody can pick items, or take them away, for somebody else.
@MainActor
@Suite("Item picks from other people")
struct ItemClaimTrustTests {
    @MainActor
    private struct Device {
        let populated: PopulatedDevice
        let expense: Expense
        let zone: CKRecordZone.ID
        var adapter: SyncStoreAdapter { populated.device.adapter }

        init() throws {
            populated = try PopulatedDevice()
            expense = try populated.addExpense()
            try FakeCloud().upload(from: populated.device)
            zone = populated.device.adapter.metadata.zoneID(forZoneName: populated.zone)
            populated.device.adapter.updateMetadata { $0.userRecordName = "_me" }
        }

        func receive(
            claimBy person: UUID, recordName: String? = nil, deleted: Bool = false, from author: String
        ) throws -> (name: String, report: ApplyReport) {
            let claim = ItemClaimRecord(
                groupID: populated.group.id.rawValue, expenseID: expense.id.rawValue, personID: person, itemIDs: [UUID()]
            )
            let name = recordName ?? claim.recordName
            // a delete comes after the claim it deletes, so only the trust check can stop it
            let later = populated.device.clock.start.addingTimeInterval(deleted ? 86_460 : 86_400)
            let record = RecordMapper.record(
                for: SyncPayload(
                    recordType: .itemClaim, recordName: name, zoneName: zone.zoneName,
                    modifiedAt: later, deletedAt: deleted ? later : nil, fields: claim.syncFields
                ), in: zone
            )
            adapter.lastModifier = { _ in author }
            return (name, try adapter.applyFetched(modifications: [record], deletions: []))
        }

        func stored(_ name: String) throws -> ItemClaimRecord? {
            try ItemClaimRecord.find(recordName: name, in: populated.device.tracker.context)
        }
    }

    @Test func aClaimForTheAuthorsOwnPersonCounts() throws {
        let device = try Device()
        let sam = CloudIdentity.personID(forUserRecordName: "_sam").rawValue
        let (name, report) = try device.receive(claimBy: sam, from: "_sam")
        #expect(report.refused.isEmpty)
        #expect(try device.stored(name)?.personID == sam)
    }

    @Test func aClaimForSomeoneElseIsRefused() throws {
        let device = try Device()
        let (name, report) = try device.receive(claimBy: device.populated.sam.id.rawValue, from: "_mallory")
        #expect(report.refused.count == 1)
        #expect(try device.stored(name) == nil)
    }

    @Test func aClaimForAPersonTheAuthorJoinedAsCounts() throws {
        let device = try Device()
        let sam = device.populated.sam.id
        try device.populated.device.services.people.claim(sam, cloudUserID: "_sam")
        let (name, report) = try device.receive(claimBy: sam.rawValue, from: "_sam")
        #expect(report.refused.isEmpty)
        #expect(try device.stored(name) != nil)
    }

    @Test func yourOwnDevicesClaimsAlwaysCount() throws {
        let device = try Device()
        let me = device.populated.me.id.rawValue
        let (mine, _) = try device.receive(claimBy: me, from: "_me")
        #expect(try device.stored(mine) != nil)
        let (current, _) = try device.receive(claimBy: device.populated.sam.id.rawValue, from: CKCurrentUserDefaultName)
        #expect(try device.stored(current) != nil)
    }

    @Test func aClaimWithAnotherIDIsRefused() throws {
        let device = try Device()
        let sam = CloudIdentity.personID(forUserRecordName: "_sam").rawValue
        let name = UUID().uuidString
        let (_, report) = try device.receive(claimBy: sam, recordName: name, from: "_sam")
        #expect(report.refused.count == 1)
        #expect(try device.stored(name) == nil)
    }

    @Test func nobodyCanDeleteSomeoneElsesClaim() throws {
        let device = try Device()
        let sam = CloudIdentity.personID(forUserRecordName: "_sam").rawValue
        let (name, _) = try device.receive(claimBy: sam, from: "_sam")
        let (_, report) = try device.receive(claimBy: sam, deleted: true, from: "_mallory")
        #expect(report.refused.count == 1)
        #expect(try device.stored(name)?.deletedAt == nil)
    }
}
