import CloudKit
import Foundation
import Testing
@testable import Splt

@Suite("Sync failures")
struct SyncFailureTests {
    @Test(arguments: [
        (CKError.Code.serverRecordChanged, SyncFailure.conflict),
        (.zoneNotFound, .zoneMissing),
        (.userDeletedZone, .zoneMissing),
        (.unknownItem, .itemMissing),
        (.networkUnavailable, .offline),
        (.networkFailure, .offline),
        (.quotaExceeded, .quotaExceeded),
        (.notAuthenticated, .noAccount),
        (.managedAccountRestricted, .restricted),
        (.permissionFailure, .noPermission),
    ])
    func codesMapToFailures(code: CKError.Code, expected: SyncFailure) {
        #expect(SyncFailure(CKError(code)) == expected)
    }

    @Test func busyServiceIsTransientAndHonoursRetryAfter() {
        let error = CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 42.0])
        #expect(SyncFailure(error) == .transient(retryAfter: 42))
        #expect(SyncFailure(error).retryAfter == 42)
        #expect(SyncFailure(CKError(.serviceUnavailable)).isRetryable)
    }

    @Test func unknownErrorsGetAFriendlyMessage() {
        struct Odd: Error {}
        guard case .other(let message) = SyncFailure(Odd()) else {
            Issue.record("expected .other")
            return
        }
        #expect(message.contains("safe"))
        #expect(SyncFailure(CKError(.internalError)).status != nil)
    }

    @Test func statusesMatchWhatThePersonShouldSee() {
        #expect(SyncFailure.offline.status == .offline)
        #expect(SyncFailure.noAccount.status == .noAccount)
        #expect(SyncFailure.restricted.status == .restricted)
        #expect(SyncFailure.conflict.status == nil)
        #expect(SyncFailure.transient(retryAfter: nil).status == nil)
        guard case .error(let message)? = SyncFailure.quotaExceeded.status else {
            Issue.record("expected an error status")
            return
        }
        #expect(message.contains("storage"))
        #expect(!message.contains("\u{2014}") && !message.contains("\u{2013}"))
    }
}

@Suite("Backoff")
struct BackoffPolicyTests {
    private let policy = BackoffPolicy()

    @Test func waitsDoubleAndStopAtTheCap() {
        let delays = (0..<8).map { policy.delay(afterFailures: $0, for: .offline) }
        #expect(delays.prefix(4) == [15, 30, 60, 120])
        #expect(delays.last == 900)
        #expect(zip(delays, delays.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func fullStorageBacksOffMuchLonger() {
        #expect(policy.delay(afterFailures: 0, for: .quotaExceeded) == 600)
        #expect(policy.delay(afterFailures: 30, for: .quotaExceeded) == 21_600)
    }

    @Test func theServersRetryHintIsNeverShortened() {
        #expect(policy.delay(afterFailures: 0, for: .transient(retryAfter: 120)) == 120)
        #expect(policy.delay(afterFailures: 0, for: .transient(retryAfter: 1)) == 15)
        #expect(policy.delay(afterFailures: -3, for: .offline) == 15)
    }
}

@Suite("Sync state store")
struct SyncStateStoreTests {
    private func sample() -> SyncMetadata {
        var metadata = SyncMetadata(userRecordName: "_me")
        metadata.zones["ZONE"] = ZoneInfo(ownerName: "__defaultOwner__", scope: .privateDatabase)
        metadata.setCopy(PersonCopy(systemFields: Data([1, 2]), sentModifiedAt: Date(timeIntervalSince1970: 100)), zoneName: "ZONE", recordName: "P")
        metadata.personQueue.insert(PersonCopyKey(zoneName: "ZONE", recordName: "Q"))
        return metadata
    }

    @Test func fileStoreSurvivesANewInstance() throws {
        let directory = URL.temporaryDirectory.appending(path: "splt-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSyncStateStore(directory: directory)
        #expect(store.loadMetadata() == SyncMetadata())
        #expect(store.loadEngineState(.privateDatabase) == nil)
        store.saveMetadata(sample())
        store.saveEngineState(Data("private".utf8), scope: .privateDatabase)
        store.saveEngineState(Data("shared".utf8), scope: .sharedDatabase)

        let again = FileSyncStateStore(directory: directory)
        #expect(again.loadMetadata() == sample())
        #expect(again.loadEngineState(.privateDatabase) == Data("private".utf8))
        #expect(again.loadEngineState(.sharedDatabase) == Data("shared".utf8))
        again.saveEngineState(nil, scope: .sharedDatabase)
        #expect(again.loadEngineState(.sharedDatabase) == nil)
        again.reset()
        #expect(again.loadMetadata() == SyncMetadata())
        #expect(again.loadEngineState(.privateDatabase) == nil)
    }

    @Test func corruptFilesReadAsEmpty() throws {
        let directory = URL.temporaryDirectory.appending(path: "splt-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "metadata.json"))
        #expect(FileSyncStateStore(directory: directory).loadMetadata() == SyncMetadata())
    }

    @Test func memoryStoreBehavesTheSame() {
        let store = InMemorySyncStateStore()
        store.saveMetadata(sample())
        store.saveEngineState(Data([9]), scope: .privateDatabase)
        #expect(store.loadMetadata() == sample())
        #expect(store.loadEngineState(.privateDatabase) == Data([9]))
        store.reset()
        #expect(store.loadMetadata() == SyncMetadata())
    }

    @Test func metadataHelpersTrackZonesAndCopies() {
        var metadata = sample()
        #expect(metadata.zonesHoldingCopy(of: "P") == ["ZONE"])
        #expect(metadata.scope(forZoneName: "ZONE") == .privateDatabase)
        #expect(metadata.scope(forZoneName: "UNKNOWN") == .privateDatabase)
        metadata.forget(zoneName: "ZONE")
        #expect(metadata.zones.isEmpty)
        #expect(metadata.personCopies.isEmpty)
        #expect(metadata.personQueue.isEmpty)
    }
}

@Suite("UUID scanner")
struct UUIDScannerTests {
    @Test func findsUUIDsInsideJSONAndText() {
        let a = UUID().uuidString
        let b = UUID().uuidString
        let json = Data("{\"payers\":[\"\(a)\",{\"minorUnits\":100},\"\(b.lowercased())\"]}".utf8)
        #expect(UUIDScanner.uuids(in: json) == [a, b])
        #expect(UUIDScanner.uuids(in: "no ids here").isEmpty)
        #expect(UUIDScanner.uuids(in: "12345678-1234-1234-1234-12345678901").isEmpty)
        #expect(UUIDScanner.uuids(in: a) == [a])
    }

    @Test func fieldsReportEveryReferencedUUID() {
        let a = UUID()
        let b = UUID()
        var fields = SyncFields()
        fields.set("createdByID", a)
        fields.set("payers", Data("[\"\(b.uuidString)\"]".utf8))
        fields.set("totalMinorUnits", Int64(5))
        #expect(fields.referencedUUIDs == [a.uuidString, b.uuidString])
    }
}
