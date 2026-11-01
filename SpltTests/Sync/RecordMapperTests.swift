import CloudKit
import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Record mapper")
struct RecordMapperTests {
    private let zoneID = CKRecordZone.ID(zoneName: "ZONE", ownerName: CKCurrentUserDefaultName)

    private func payloads(of populated: PopulatedDevice) throws -> [SyncPayload] {
        let tracker = populated.device.tracker
        return try tracker.pendingChanges().compactMap {
            try tracker.payload(recordType: $0.recordType, recordName: $0.recordName)
        }
    }

    @Test func everyRecordTypeRoundTrips() throws {
        let populated = try PopulatedDevice()
        try populated.addEverythingElse()
        let all = try payloads(of: populated)
        #expect(Set(all.map(\.recordType)).isSuperset(of: Set(SyncRecordType.allCases)))
        for payload in all {
            let record = RecordMapper.record(for: payload, in: zoneID)
            #expect(record.recordType == payload.recordType.rawValue)
            #expect(record.recordID.recordName == payload.recordName)
            let back = try RecordMapper.payload(from: record)
            #expect(back.fields == payload.fields)
            #expect(back.modifiedAt == payload.modifiedAt)
            #expect(back.deletedAt == payload.deletedAt)
            #expect(back.recordName == payload.recordName)
            #expect(back.recordType == payload.recordType)
            #expect(back.zoneName == "ZONE")
        }
    }

    @Test func schemaCoversEveryStoredField() throws {
        let populated = try PopulatedDevice()
        try populated.addEverythingElse()
        for payload in try payloads(of: populated) {
            let known = Set(RecordSchema.fields(for: payload.recordType).keys)
            let used = Set(payload.fields.values.keys)
            #expect(used.isSubset(of: known), "\(payload.recordType) writes fields the schema lacks: \(used.subtracting(known))")
        }
    }

    @Test func schemaKindsMatchTheStoredValueKinds() throws {
        let populated = try PopulatedDevice()
        try populated.addEverythingElse()
        for payload in try payloads(of: populated) {
            let schema = RecordSchema.fields(for: payload.recordType)
            for (key, value) in payload.fields.values {
                switch (schema[key], value) {
                case (.string?, .string), (.int?, .int), (.double?, .double), (.date?, .date), (.data?, .data): break
                default: Issue.record("\(payload.recordType).\(key) has the wrong kind in the schema")
                }
            }
        }
    }

    @Test func extremeNumbersSurvive() throws {
        var fields = SyncFields()
        fields.set("totalMinorUnits", Int64.max)
        fields.set("latitude", 38.722252)
        fields.set("longitude", -9.139337)
        fields.set("title", "Café \u{1F37D} \"quoted\"\nsecond line")
        let payload = SyncPayload(
            recordType: .expense, recordName: UUID().uuidString, modifiedAt: Date(timeIntervalSince1970: 1_750_000_123.456),
            fields: fields
        )
        let back = try RecordMapper.payload(from: RecordMapper.record(for: payload, in: zoneID))
        #expect(back.fields.int("totalMinorUnits") == Int64.max)
        #expect(back.fields.double("latitude") == 38.722252)
        #expect(back.fields.double("longitude") == -9.139337)
        #expect(back.fields.string("title") == payload.fields.string("title"))
        #expect(back.modifiedAt == payload.modifiedAt)
    }

    @Test func tombstonesCarryTheirDeleteDate() throws {
        let deleted = Date(timeIntervalSince1970: 1_750_000_500)
        let payload = SyncPayload(
            recordType: .expense, recordName: UUID().uuidString, modifiedAt: deleted, deletedAt: deleted
        )
        let back = try RecordMapper.payload(from: RecordMapper.record(for: payload, in: zoneID))
        #expect(back.deletedAt == deleted)
        let alive = SyncPayload(recordType: .expense, recordName: payload.recordName, modifiedAt: deleted)
        #expect(try RecordMapper.payload(from: RecordMapper.record(for: alive, in: zoneID)).deletedAt == nil)
    }

    @Test func clearedOptionalFieldsAreClearedOnTheRecord() throws {
        var fields = SyncFields()
        fields.set("locationName", "Lisbon")
        let name = UUID().uuidString
        let first = SyncPayload(recordType: .expense, recordName: name, modifiedAt: .now, fields: fields)
        let record = RecordMapper.record(for: first, in: zoneID)
        #expect(record["locationName"] as? String == "Lisbon")
        let second = SyncPayload(
            recordType: .expense, recordName: name, systemFields: RecordMapper.encodeSystemFields(record),
            modifiedAt: .now, fields: SyncFields()
        )
        let updated = RecordMapper.record(for: second, in: zoneID, systemFields: second.systemFields)
        #expect(updated["locationName"] == nil)
    }

    @Test func systemFieldsRestoreTheRecordIdentity() throws {
        let payload = SyncPayload(recordType: .group, recordName: UUID().uuidString, modifiedAt: .now)
        let record = RecordMapper.record(for: payload, in: zoneID)
        let data = RecordMapper.encodeSystemFields(record)
        let restored = try #require(RecordMapper.decodeSystemFields(data))
        #expect(restored.recordID == record.recordID)
        #expect(restored.recordType == "Group")
        #expect(restored.allKeys().isEmpty)
        let rebuilt = RecordMapper.record(for: payload, in: zoneID, systemFields: data)
        #expect(rebuilt.recordID == record.recordID)
    }

    @Test func systemFieldsFromAnotherZoneAreIgnored() throws {
        let payload = SyncPayload(recordType: .person, recordName: UUID().uuidString, modifiedAt: .now)
        let other = CKRecordZone.ID(zoneName: "OTHER", ownerName: CKCurrentUserDefaultName)
        let data = RecordMapper.encodeSystemFields(RecordMapper.record(for: payload, in: other))
        let record = RecordMapper.record(for: payload, in: zoneID, systemFields: data)
        #expect(record.recordID.zoneID == zoneID)
        #expect(RecordMapper.decodeSystemFields(Data([1, 2, 3])) == nil)
    }

    @Test func unknownTypesAndIncompleteRecordsAreRejected() {
        let unknown = CKRecord(recordType: "Mystery", recordID: CKRecord.ID(recordName: "x", zoneID: zoneID))
        #expect(throws: RecordMapperError.unknownRecordType("Mystery")) { try RecordMapper.payload(from: unknown) }
        let bare = CKRecord(recordType: "Expense", recordID: CKRecord.ID(recordName: "y", zoneID: zoneID))
        #expect(throws: RecordMapperError.missingModifiedDate("y")) { try RecordMapper.payload(from: bare) }
    }

    @Test func fieldsAddedByAnewerAppAreIgnored() throws {
        let payload = SyncPayload(recordType: .payment, recordName: UUID().uuidString, modifiedAt: .now)
        let record = RecordMapper.record(for: payload, in: zoneID)
        record["futureField"] = "from a newer version" as NSString
        let back = try RecordMapper.payload(from: record)
        #expect(back.fields.string("futureField") == nil)
    }
}
