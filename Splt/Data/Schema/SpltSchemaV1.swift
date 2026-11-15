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

/// The shape Splt 1.1 saved. Version 2 adds a group's cover photo and default split, and each person's
/// claims on the items of a receipt. Its models are frozen copies in `SpltSchemaV2Models.swift`.
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

/// The current shape of the store. Version 3 changes no data: it indexes the columns lists are fetched and
/// sorted by, such as an expense's group and date, so opening a big group no longer scans the whole table.
enum SpltSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

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

typealias PersonRecord = SpltSchemaV3.PersonRecord
typealias GroupRecord = SpltSchemaV3.GroupRecord
typealias ExpenseRecord = SpltSchemaV3.ExpenseRecord
typealias PaymentRecord = SpltSchemaV3.PaymentRecord
typealias CommentRecord = SpltSchemaV3.CommentRecord
typealias ActivityRecord = SpltSchemaV3.ActivityRecord
typealias RecurringExpenseRecord = SpltSchemaV3.RecurringExpenseRecord
typealias ItemClaimRecord = SpltSchemaV3.ItemClaimRecord
