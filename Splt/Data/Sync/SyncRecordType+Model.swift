extension SyncRecordType {
    var modelType: any SyncTracked.Type {
        switch self {
        case .person: PersonRecord.self
        case .group: GroupRecord.self
        case .expense: ExpenseRecord.self
        case .payment: PaymentRecord.self
        case .comment: CommentRecord.self
        case .activity: ActivityRecord.self
        case .recurringExpense: RecurringExpenseRecord.self
        case .itemClaim: ItemClaimRecord.self
        }
    }
}
