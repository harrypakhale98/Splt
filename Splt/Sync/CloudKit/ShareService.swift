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

extension CKRecordZone.ID {
    /// The record that shares this whole zone.
    var zoneWideShareID: CKRecord.ID { CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: self) }
}

/// Creates, finds and removes the CKShare of a group's record zone.
struct ShareService {
    let privateDatabase: any ShareDatabase
    let sharedDatabase: any ShareDatabase

    /// The zone wide share for a group in your private database, created on first use.
    /// Invitees can read and write. Without `anyoneWithLink` nobody can join without being invited by
    /// name; with it, anyone who has the link can join, which is what a link or QR code needs.
    /// A share that is already open is never closed here; the owner does that in the invite sheet.
    func prepare(zoneID: CKRecordZone.ID, title: String, anyoneWithLink: Bool = false) async throws -> CKShare {
        let share: CKShare
        if let existing = try await existingShare(zoneID: zoneID, in: privateDatabase) {
            guard anyoneWithLink, existing.publicPermission == .none else { return existing }
            share = existing
        } else {
            share = CKShare(recordZoneID: zoneID)
            share[CKShare.SystemFieldKey.title] = title as NSString
        }
        share.publicPermission = anyoneWithLink ? .readWrite : .none
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
        do {
            return try await database.fetchRecord(zoneID.zoneWideShareID) as? CKShare
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
