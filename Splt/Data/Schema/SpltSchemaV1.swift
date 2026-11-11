import SwiftData

/// The first shipped shape of the store, as 1.0 saved it. Its models are frozen copies in
/// `SpltSchemaV1Models.swift`, so a store from 1.0 can be opened and migrated to the current version.
enum SpltSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            PersonRecord.self,
            GroupRecord.self,
            ExpenseRecord.self,
            PaymentRecord.self,
            CommentRecord.self,
            ActivityRecord.self,
            RecurringExpenseRecord.self
        ]
    }
}

/// The current shape of the store. Version 2 adds a group's cover photo and default split, and
/// each person's claims on the items of a receipt.
enum SpltSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            PersonRecord.self,
            GroupRecord.self,
            ExpenseRecord.self,
            PaymentRecord.self,
            CommentRecord.self,
            ActivityRecord.self,
            RecurringExpenseRecord.self,
            ItemClaimRecord.self
        ]
    }
}

typealias PersonRecord = SpltSchemaV2.PersonRecord
typealias GroupRecord = SpltSchemaV2.GroupRecord
typealias ExpenseRecord = SpltSchemaV2.ExpenseRecord
typealias PaymentRecord = SpltSchemaV2.PaymentRecord
typealias CommentRecord = SpltSchemaV2.CommentRecord
typealias ActivityRecord = SpltSchemaV2.ActivityRecord
typealias RecurringExpenseRecord = SpltSchemaV2.RecurringExpenseRecord
typealias ItemClaimRecord = SpltSchemaV2.ItemClaimRecord
