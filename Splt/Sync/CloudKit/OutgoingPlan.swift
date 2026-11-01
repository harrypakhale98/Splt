import CloudKit
import Foundation

extension CKRecordZone.ID {
    /// Zones in your own private database carry the default owner name; shared zones carry the owner's.
    var scope: DatabaseScope {
        ownerName == CKCurrentUserDefaultName ? .privateDatabase : .sharedDatabase
    }
}

/// What has to be sent to CloudKit, worked out from the dirty records in the data store.
struct OutgoingPlan: Equatable {
    var saves: [CKRecord.ID] = []
    var deletes: [CKRecord.ID] = []
    /// Private zones that may not exist on the server yet.
    var zonesToSave: [CKRecordZone.ID] = []
    /// Private zones of groups that were deleted.
    var zonesToDelete: [CKRecordZone.ID] = []
    /// Shared zones of groups this person removed, which means leaving the share.
    var zonesToLeave: [CKRecordZone.ID] = []

    var isEmpty: Bool {
        saves.isEmpty && deletes.isEmpty && zonesToSave.isEmpty && zonesToDelete.isEmpty && zonesToLeave.isEmpty
    }

    /// The part of the plan that belongs to one database.
    func part(for scope: DatabaseScope) -> OutgoingPlan {
        OutgoingPlan(
            saves: saves.filter { $0.zoneID.scope == scope },
            deletes: deletes.filter { $0.zoneID.scope == scope },
            zonesToSave: scope == .privateDatabase ? zonesToSave : [],
            zonesToDelete: scope == .privateDatabase ? zonesToDelete : [],
            zonesToLeave: scope == .sharedDatabase ? zonesToLeave : []
        )
    }
}
