import CloudKit
import Foundation

/// The three database calls sharing needs, so the logic can run against in memory records.
protocol ShareDatabase: Sendable {
    func fetchRecord(_ id: CKRecord.ID) async throws -> CKRecord
    func saveRecord(_ record: CKRecord) async throws -> CKRecord
    func deleteRecord(_ id: CKRecord.ID) async throws
}

struct CloudKitShareDatabase: ShareDatabase {
    let database: CKDatabase

    func fetchRecord(_ id: CKRecord.ID) async throws -> CKRecord {
        try await database.record(for: id)
    }

    func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        let result = try await database.modifyRecords(saving: [record], deleting: [])
        guard let saved = try result.saveResults[record.recordID]?.get() else { throw SyncError.notReady }
        return saved
    }

    func deleteRecord(_ id: CKRecord.ID) async throws {
        _ = try await database.deleteRecord(withID: id)
    }
}

/// Creates, finds and removes the CKShare of a group's record zone.
struct ShareService {
    let privateDatabase: any ShareDatabase
    let sharedDatabase: any ShareDatabase

    /// The zone wide share for a group in your private database, created on first use.
    /// Invitees can read and write, and nobody can join without being invited.
    func prepare(zoneID: CKRecordZone.ID, title: String) async throws -> CKShare {
        if let existing = try await existingShare(zoneID: zoneID, in: privateDatabase) {
            return existing
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title as NSString
        share.publicPermission = .none
        guard let saved = try await privateDatabase.saveRecord(share) as? CKShare else {
            throw SyncError.notReady
        }
        return saved
    }

    /// The share of a zone in either database, or nil when the zone is not shared.
    func share(zoneID: CKRecordZone.ID) async throws -> CKShare? {
        try await existingShare(zoneID: zoneID, in: zoneID.scope == .privateDatabase ? privateDatabase : sharedDatabase)
    }

    private func existingShare(zoneID: CKRecordZone.ID, in database: any ShareDatabase) async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await database.fetchRecord(id) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }
}

/// Reads the account state through a real container. Only create this after the entitlement check.
struct CloudKitAccountProbe: AccountProbe {
    func availability(containerIdentifier: String) async -> AccountAvailability {
        let container = CKContainer(identifier: containerIdentifier)
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .couldNotDetermine, .temporarilyUnavailable: return .unknown
            @unknown default: return .unknown
            }
        } catch {
            return .unknown
        }
    }
}
