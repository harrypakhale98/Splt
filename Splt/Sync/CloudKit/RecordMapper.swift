import CloudKit
import Foundation

enum RecordMapperError: Error, Equatable {
    case unknownRecordType(String)
    case missingModifiedDate(String)
}

/// Converts between the sync payloads of the data layer and `CKRecord`s. Pure: no network, no store.
enum RecordMapper {
    static func zoneID(zoneName: String, ownerName: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    static func recordID(recordName: String, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    /// Builds the record to upload. When `systemFields` from the last sync are given and match the
    /// record, the upload carries the change tag the server needs to detect a conflicting edit.
    static func record(
        for payload: SyncPayload, in zoneID: CKRecordZone.ID, systemFields: Data? = nil
    ) -> CKRecord {
        let id = recordID(recordName: payload.recordName, zoneID: zoneID)
        let record: CKRecord
        if let restored = systemFields.flatMap(decodeSystemFields), restored.recordID == id,
           restored.recordType == payload.recordType.rawValue {
            record = restored
        } else {
            record = CKRecord(recordType: payload.recordType.rawValue, recordID: id)
        }
        record[RecordSchema.schemaVersionKey] = NSNumber(value: RecordSchema.currentVersion)
        record[RecordSchema.modifiedAtKey] = payload.modifiedAt as NSDate
        record[RecordSchema.deletedAtKey] = payload.deletedAt.map { $0 as NSDate }
        for (key, kind) in RecordSchema.fields(for: payload.recordType) {
            record[key] = recordValue(payload.fields, key: key, kind: kind)
        }
        return record
    }

    /// Reads a record from the server. The payload carries the zone name and the encoded system
    /// fields, which the caller may replace when the record is a copy that lives in several zones.
    static func payload(from record: CKRecord) throws -> SyncPayload {
        guard let type = SyncRecordType(rawValue: record.recordType) else {
            throw RecordMapperError.unknownRecordType(record.recordType)
        }
        guard let modifiedAt = record[RecordSchema.modifiedAtKey] as? Date else {
            throw RecordMapperError.missingModifiedDate(record.recordID.recordName)
        }
        var fields = SyncFields()
        for (key, kind) in RecordSchema.fields(for: type) {
            read(record, key: key, kind: kind, into: &fields)
        }
        return SyncPayload(
            recordType: type,
            recordName: record.recordID.recordName,
            zoneName: record.recordID.zoneID.zoneName,
            systemFields: encodeSystemFields(record),
            modifiedAt: modifiedAt,
            deletedAt: record[RecordSchema.deletedAtKey] as? Date,
            fields: fields
        )
    }

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    private static func recordValue(_ fields: SyncFields, key: String, kind: FieldKind) -> CKRecordValue? {
        switch kind {
        case .string: fields.string(key).map { $0 as NSString }
        case .int: fields.int(key).map { NSNumber(value: $0) }
        case .double: fields.double(key).map { NSNumber(value: $0) }
        case .date: fields.date(key).map { $0 as NSDate }
        case .data: fields.data(key).map { $0 as NSData }
        }
    }

    private static func read(_ record: CKRecord, key: String, kind: FieldKind, into fields: inout SyncFields) {
        switch kind {
        case .string: fields.set(key, record[key] as? String)
        case .int: fields.set(key, (record[key] as? NSNumber)?.int64Value)
        case .double: fields.set(key, (record[key] as? NSNumber)?.doubleValue)
        case .date: fields.set(key, record[key] as? Date)
        case .data: fields.set(key, record[key] as? Data)
        }
    }
}
