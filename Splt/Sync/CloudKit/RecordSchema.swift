import Foundation

/// The shape of a stored field. CloudKit hands numbers back as one number type, so the schema
/// says whether a field is a whole number or a fraction.
enum FieldKind: Sendable {
    case string
    case int
    case double
    case date
    case data
}

/// The CloudKit record types and fields Splt uses. This is the schema to deploy to production.
enum RecordSchema {
    /// Bookkeeping fields on every record, next to the domain fields below.
    static let modifiedAtKey = "modifiedAt"
    static let deletedAtKey = "deletedAt"
    static let schemaVersionKey = "schemaVersion"
    static let currentVersion: Int64 = 1

    static func fields(for type: SyncRecordType) -> [String: FieldKind] {
        switch type {
        case .person:
            [
                "name": .string, "contactHint": .string, "kind": .string, "claimedByCloudUserID": .string,
                "avatarSeed": .int, "createdAt": .date,
            ]
        case .group:
            [
                "name": .string, "symbol": .string, "currencyCode": .string, "kind": .string,
                "memberIDs": .data, "simplifiesDebts": .int, "isArchived": .int, "tripStart": .date,
                "tripEnd": .date, "pinnedRate": .data, "createdAt": .date,
            ]
        case .expense:
            [
                "groupID": .string, "title": .string, "totalMinorUnits": .int, "currencyCode": .string,
                "date": .date, "category": .string, "payers": .data, "split": .data, "note": .string,
                "receiptFileName": .string, "locationName": .string, "latitude": .double,
                "longitude": .double, "recurrence": .data, "recurringExpenseID": .string,
                "editHistory": .data, "createdByID": .string, "createdAt": .date,
            ]
        case .payment:
            [
                "groupID": .string, "payerID": .string, "receiverID": .string, "amountMinorUnits": .int,
                "currencyCode": .string, "date": .date, "note": .string, "createdAt": .date,
            ]
        case .comment:
            [
                "groupID": .string, "expenseID": .string, "authorID": .string, "text": .string,
                "createdAt": .date, "editedAt": .date, "reactions": .data,
            ]
        case .activity:
            [
                "groupID": .string, "actorID": .string, "kind": .string, "event": .data, "createdAt": .date,
            ]
        case .recurringExpense:
            [
                "groupID": .string, "title": .string, "totalMinorUnits": .int, "currencyCode": .string,
                "category": .string, "payers": .data, "split": .data, "note": .string, "rule": .data,
                "lastCreatedOccurrence": .date, "isActive": .int, "createdByID": .string,
                "createdAt": .date,
            ]
        }
    }
}
