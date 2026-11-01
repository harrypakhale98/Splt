import SwiftData

/// The first shipped shape of the store. The models live inside this namespace so a later
/// schema can keep a frozen copy of them while the top level names move on.
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

typealias PersonRecord = SpltSchemaV1.PersonRecord
typealias GroupRecord = SpltSchemaV1.GroupRecord
typealias ExpenseRecord = SpltSchemaV1.ExpenseRecord
typealias PaymentRecord = SpltSchemaV1.PaymentRecord
typealias CommentRecord = SpltSchemaV1.CommentRecord
typealias ActivityRecord = SpltSchemaV1.ActivityRecord
typealias RecurringExpenseRecord = SpltSchemaV1.RecurringExpenseRecord
