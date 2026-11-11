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

    /// Every changed field with its value before and after, for the activity entry of an edit.
    static func changes(
        from old: Expense, to new: Expense, oldExtras: ExpenseExtras, newExtras: ExpenseExtras
    ) -> [ExpenseChange] {
        changedFields(from: old, to: new, oldExtras: oldExtras, newExtras: newExtras).map { field in
            let (before, after) = values(of: field, old: old, new: new, oldExtras: oldExtras, newExtras: newExtras)
            return ExpenseChange(field: field, before: before, after: after)
        }
    }

    private static func values(
        of field: ExpenseField, old: Expense, new: Expense, oldExtras: ExpenseExtras, newExtras: ExpenseExtras
    ) -> (ExpenseChangeValue?, ExpenseChangeValue?) {
        switch field {
        case .title:
            return (.text(old.title), .text(new.title))
        case .total:
            return (.money(old.total), .money(new.total))
        case .date:
            return (.date(old.date), .date(new.date))
        case .category:
            return (.text(old.category.rawValue), .text(new.category.rawValue))
        case .payers:
            return (
                .payers(old.payers, currencyCode: old.total.currencyCode),
                .payers(new.payers, currencyCode: new.total.currencyCode)
            )
        case .split:
            return (.split(old.split), .split(new.split))
        case .note:
            return (old.note.isEmpty ? nil : .text(old.note), new.note.isEmpty ? nil : .text(new.note))
        case .group:
            return (old.groupID.map(ExpenseChangeValue.group), new.groupID.map(ExpenseChangeValue.group))
        case .receipt:
            return (oldExtras.receiptFileName.map { _ in .present }, newExtras.receiptFileName.map { _ in .present })
        case .location:
            return (location(oldExtras.location), location(newExtras.location))
        case .recurrence:
            return (
                oldExtras.recurrence.map { .text($0.frequency.rawValue) },
                newExtras.recurrence.map { .text($0.frequency.rawValue) }
            )
        }
    }

    private static func location(_ location: ExpenseLocation?) -> ExpenseChangeValue? {
        guard let location else { return nil }
        return ExpenseChangeValue(text: location.name)
    }
}
