import SpltCore

/// Works out which fields an edit touched, for the edit history.
enum ExpenseDiff {
    static func changedFields(
        from old: Expense, to new: Expense, oldExtras: ExpenseExtras, newExtras: ExpenseExtras
    ) -> [ExpenseField] {
        var fields: [ExpenseField] = []
        if old.title != new.title { fields.append(.title) }
        if old.total != new.total { fields.append(.total) }
        if old.date != new.date { fields.append(.date) }
        if old.category != new.category { fields.append(.category) }
        if old.payers != new.payers { fields.append(.payers) }
        if old.split != new.split { fields.append(.split) }
        if old.note != new.note { fields.append(.note) }
        if old.groupID != new.groupID { fields.append(.group) }
        if oldExtras.receiptFileName != newExtras.receiptFileName { fields.append(.receipt) }
        if oldExtras.location != newExtras.location { fields.append(.location) }
        if oldExtras.recurrence != newExtras.recurrence { fields.append(.recurrence) }
        return fields
    }
}
