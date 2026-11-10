import CloudKit
import Foundation
import Synchronization
@testable import Splt

/// A stand in for CKSyncEngine that remembers what was queued.
@MainActor
final class FakeEngineHandle: SyncEngineHandle {
    private(set) var recordChanges: [CKSyncEngine.PendingRecordZoneChange] = []
    private(set) var databaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
    private(set) var sendCount = 0
    private(set) var fetchCount = 0
    private(set) var cancelCount = 0
    var fetchError: (any Error)?
    var sendError: (any Error)?

    func add(pendingRecordZoneChanges changes: [CKSyncEngine.PendingRecordZoneChange]) {
        recordChanges += changes
    }

    func add(pendingDatabaseChanges changes: [CKSyncEngine.PendingDatabaseChange]) {
        databaseChanges += changes
    }

    func remove(pendingRecordZoneChanges changes: [CKSyncEngine.PendingRecordZoneChange]) {
        recordChanges.removeAll { changes.contains($0) }
    }

    func sendChanges() async throws {
        sendCount += 1
        if let sendError { throw sendError }
    }

    /// What a fetch that goes through delivers, for a stand in server that has something to say.
    var onFetch: (@MainActor () -> Void)?

    func fetchChanges() async throws {
        fetchCount += 1
        if let fetchError { throw fetchError }
        onFetch?()
    }

    func cancelOperations() async {
        cancelCount += 1
    }

    var savedRecordIDs: [CKRecord.ID] {
        recordChanges.compactMap { if case .saveRecord(let id) = $0 { id } else { nil } }
    }

    var deletedRecordIDs: [CKRecord.ID] {
        recordChanges.compactMap { if case .deleteRecord(let id) = $0 { id } else { nil } }
    }

    var savedZoneIDs: [CKRecordZone.ID] {
        databaseChanges.compactMap { if case .saveZone(let zone) = $0 { zone.zoneID } else { nil } }
    }

    var deletedZoneIDs: [CKRecordZone.ID] {
        databaseChanges.compactMap { if case .deleteZone(let id) = $0 { id } else { nil } }
    }

    /// The zones being left: a participant leaves by deleting the zone's share record.
    var leftZoneIDs: [CKRecordZone.ID] {
        deletedRecordIDs.filter { $0.recordName == CKRecordNameZoneWideShare }.map(\.zoneID)
    }
}

/// A database of in memory records for sharing tests.
final class FakeShareDatabase: ShareDatabase, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [CKRecord.ID: CKRecord] = [:]
    private var saves = 0
    var fetchError: (any Error)?

    func fetchRecord(_ id: CKRecord.ID) async throws -> CKRecord {
        if let fetchError { throw fetchError }
        guard let record = lock.withLock({ records[id] }) else { throw CKError(.unknownItem) }
        return record
    }

    func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        lock.withLock {
            records[record.recordID] = record
            saves += 1
        }
        return record
    }

    func deleteRecord(_ id: CKRecord.ID) async throws {
        guard lock.withLock({ records.removeValue(forKey: id) }) != nil else { throw CKError(.unknownItem) }
    }

    func put(_ record: CKRecord) {
        lock.withLock { records[record.recordID] = record }
    }

    func contains(_ id: CKRecord.ID) -> Bool {
        lock.withLock { records[id] != nil }
    }

    var saveCount: Int { lock.withLock { saves } }
}

enum FakeBackendError: Error, Equatable {
    case noContainer
}

/// A CloudKit container stand in. It cannot make a `GroupShare`, which needs a real container.
@MainActor
final class FakeCloudKitBackend: CloudKitBackend {
    let containerIdentifier = "iCloud.com.example.app"
    let privateHandle = FakeEngineHandle()
    let sharedHandle = FakeEngineHandle()
    let privateDatabase = FakeShareDatabase()
    let sharedDatabase = FakeShareDatabase()
    var userResult: Result<String, any Error> = .success("_alice")
    private(set) var madeEngines: [DatabaseScope] = []
    /// The device this server belongs to. With it set, a fetch lists every zone the device knows of,
    /// the way a server that has lost nothing does for an engine that starts with no saved state.
    var store: (any SyncStateStore)?

    func userRecordName() async throws -> String {
        try userResult.get()
    }

    func engineFactory(for scope: DatabaseScope) -> DatabaseSyncer.EngineFactory {
        madeEngines.append(scope)
        let handle = scope == .privateDatabase ? privateHandle : sharedHandle
        return { [weak self] _, delegate in
            handle.onFetch = { [weak syncer = delegate as? DatabaseSyncer] in
                guard let zones = self?.store?.loadMetadata().zones else { return }
                let listed = zones.filter { $0.value.scope == scope }.map { CKRecordZone.ID(zoneName: $0.key, ownerName: $0.value.ownerName) }
                if !listed.isEmpty { syncer?.handle(.fetchedZones(modified: listed, deleted: [])) }
            }
            return handle
        }
    }

    var shareService: ShareService {
        ShareService(privateDatabase: privateDatabase, sharedDatabase: sharedDatabase)
    }

    func groupShare(_ share: CKShare, groupName: String) throws -> GroupShare {
        throw FakeBackendError.noContainer
    }

    func accept(_ metadata: CKShare.Metadata) async throws {}
}
