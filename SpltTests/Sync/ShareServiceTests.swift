import CloudKit
import Foundation
import Testing
@testable import Splt

@Suite("Share service")
struct ShareServiceTests {
    private let zone = CKRecordZone.ID(zoneName: UUID().uuidString, ownerName: CKCurrentUserDefaultName)
    private let sharedZone = CKRecordZone.ID(zoneName: UUID().uuidString, ownerName: "_owner")

    private func make() -> (service: ShareService, privateDatabase: FakeShareDatabase, sharedDatabase: FakeShareDatabase) {
        let privateDatabase = FakeShareDatabase()
        let sharedDatabase = FakeShareDatabase()
        return (ShareService(privateDatabase: privateDatabase, sharedDatabase: sharedDatabase), privateDatabase, sharedDatabase)
    }

    private func shareID(_ zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
    }

    @Test func aFirstShareIsZoneWidePrivateAndTitled() async throws {
        let (service, privateDatabase, _) = make()
        let share = try await service.prepare(zoneID: zone, title: "Lisbon Trip")
        #expect(share.recordID == shareID(zone))
        #expect(share.publicPermission == CKShare.ParticipantPermission.none)
        #expect(share[CKShare.SystemFieldKey.title] as? String == "Lisbon Trip")
        #expect(privateDatabase.contains(shareID(zone)))
        #expect(privateDatabase.saveCount == 1)
    }

    @Test func preparingAgainReusesTheShare() async throws {
        let (service, privateDatabase, _) = make()
        let first = try await service.prepare(zoneID: zone, title: "Lisbon Trip")
        let second = try await service.prepare(zoneID: zone, title: "Renamed")
        #expect(second.recordID == first.recordID)
        #expect(privateDatabase.saveCount == 1)
    }

    @Test func otherFetchErrorsAreNotMistakenForNoShare() async {
        let (service, privateDatabase, _) = make()
        privateDatabase.fetchError = CKError(.networkUnavailable)
        await #expect(throws: CKError.self) { try await service.prepare(zoneID: zone, title: "x") }
        #expect(privateDatabase.saveCount == 0)
    }

    @Test func aMissingZoneMeansNotShared() async throws {
        let (service, privateDatabase, _) = make()
        privateDatabase.fetchError = CKError(.zoneNotFound)
        #expect(try await service.share(zoneID: zone) == nil)
    }

    @Test func lookingUpAShareUsesTheRightDatabase() async throws {
        let (service, privateDatabase, sharedDatabase) = make()
        sharedDatabase.put(CKShare(recordZoneID: sharedZone))
        #expect(try await service.share(zoneID: sharedZone)?.recordID == shareID(sharedZone))
        #expect(try await service.share(zoneID: zone) == nil)
        privateDatabase.put(CKShare(recordZoneID: zone))
        #expect(try await service.share(zoneID: zone) != nil)
    }
}
