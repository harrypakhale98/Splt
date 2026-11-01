import CloudKit
import Foundation

/// Creates, finds and removes the CKShare of a group's record zone.
struct ShareService {
    let container: CKContainer

    /// The zone wide share for a group in your private database, created on first use.
    /// Invitees can read and write, and nobody can join without being invited.
    func prepare(zoneID: CKRecordZone.ID, title: String) async throws -> CKShare {
        let database = container.privateCloudDatabase
        if let existing = try await existingShare(zoneID: zoneID, in: database) {
            return existing
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title as NSString
        share.publicPermission = .none
        let result = try await database.modifyRecords(saving: [share], deleting: [])
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw SyncError.notReady
        }
        return saved
    }

    /// The share of a zone in either database, or nil when the zone is not shared.
    func existingShare(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await database.record(for: id) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    func share(zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let database = zoneID.scope == .privateDatabase ? container.privateCloudDatabase : container.sharedCloudDatabase
        return try await existingShare(zoneID: zoneID, in: database)
    }

    /// Stops sharing. The group stays in your private database.
    func stopSharing(zoneID: CKRecordZone.ID) async throws {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            _ = try await container.privateCloudDatabase.deleteRecord(withID: id)
        } catch let error as CKError where error.code == .unknownItem {
            throw SyncError.notShared
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
