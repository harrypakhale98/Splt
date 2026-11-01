import Foundation

/// One record as the sync engine sees it, either read from the store to upload or received from the server.
struct SyncPayload: Hashable, Sendable {
    var recordType: SyncRecordType
    var recordName: String
    var zoneName: String?
    var systemFields: Data?
    var modifiedAt: Date
    var deletedAt: Date?
    var fields: SyncFields

    init(
        recordType: SyncRecordType,
        recordName: String,
        zoneName: String? = nil,
        systemFields: Data? = nil,
        modifiedAt: Date,
        deletedAt: Date? = nil,
        fields: SyncFields = SyncFields()
    ) {
        self.recordType = recordType
        self.recordName = recordName
        self.zoneName = zoneName
        self.systemFields = systemFields
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.fields = fields
    }

    var stamp: SyncStamp {
        SyncStamp(modifiedAt: modifiedAt, deletedAt: deletedAt, tieBreaker: fields.canonicalText)
    }
}

/// A local change waiting to be sent.
struct PendingChange: Hashable, Sendable {
    var recordType: SyncRecordType
    var recordName: String
    var zoneName: String?
    var operation: PendingOperation
    var modifiedAt: Date
}
