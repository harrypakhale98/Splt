import Foundation
import SpltCore

extension ExpenseFormModel {
    enum SaveFailure: Error {
        case notReady
    }

    /// The expense the form describes right now, or nil while something blocks saving.
    func makeExpense() -> Expense? {
        guard let group, let total, issue == nil,
              case .payers(let payers) = payer.payers(total: total, locale: locale),
              case .definition(let definition) = split.definition(
                participants: participants, currencyCode: currencyCode, locale: locale
              ) else { return nil }
        return Expense(
            id: original?.id ?? ExpenseID(),
            groupID: group.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            total: total,
            date: date,
            category: category,
            payers: payers,
            split: definition,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Saves the expense or template and returns the stored expense. Throws `SaveFailure.notReady`
    /// when `canSave` is false, or the repository's error.
    @discardableResult
    func save() throws -> Expense {
        if let savedExpense { return savedExpense }
        guard canSave, var expense = makeExpense() else { throw SaveFailure.notReady }
        switch mode {
        case .add:
            try saveNew(&expense)
            dependencies.defaults.set(expense.groupID?.description, forKey: Self.lastGroupKey)
        case .edit:
            try saveEdit(expense)
        case .editRecurring:
            try saveTemplate(expense)
        }
        saveCount += 1
        savedExpense = expense
        return expense
    }

    private func saveNew(_ expense: inout Expense) throws {
        var extras = ExpenseExtras()
        let storedName = try storeNewReceipt()
        extras.receiptFileName = storedName
        do {
            if let frequency = repeatChoice.frequency {
                let rule = RecurrenceRule(frequency: frequency, startDate: expense.date, endDate: repeatChoice.endDate)
                let template = RecurringExpense(
                    groupID: expense.groupID, title: expense.title, total: expense.total, category: expense.category,
                    payers: expense.payers, split: expense.split, note: expense.note, rule: rule,
                    lastCreatedOccurrence: expense.date, createdBy: me?.id, createdAt: dependencies.now()
                )
                expense.id = OccurrenceID.expenseID(template: template.id, occurrence: expense.date)
                extras.recurrence = rule
                extras.recurringExpenseID = template.id
                try services.recurring.add(template)
                do {
                    try services.expenses.add(expense, extras: extras)
                } catch {
                    try? services.recurring.delete(id: template.id)
                    throw error
                }
            } else {
                try services.expenses.add(expense, extras: extras)
            }
        } catch {
            if let storedName { dependencies.receipts.delete(storedName) }
            throw error
        }
    }

    private func saveEdit(_ expense: Expense) throws {
        var extras = originalExtras
        let oldName = originalExtras.receiptFileName
        let newName = try storeNewReceipt()
        if let newName {
            extras.receiptFileName = newName
        } else if receipt.storedFileName == nil {
            extras.receiptFileName = nil
        }
        do {
            try services.expenses.update(expense, extras: extras)
        } catch {
            if let newName { dependencies.receipts.delete(newName) }
            throw error
        }
        if let oldName, oldName != extras.receiptFileName {
            dependencies.receipts.delete(oldName)
        }
    }

    private func saveTemplate(_ expense: Expense) throws {
        guard var updated = template else { throw SaveFailure.notReady }
        updated.title = expense.title
        updated.total = expense.total
        updated.category = expense.category
        updated.payers = expense.payers
        updated.split = expense.split
        updated.note = expense.note
        if let frequency = repeatChoice.frequency { updated.rule.frequency = frequency }
        updated.rule.endDate = repeatChoice.endDate
        try services.recurring.update(updated)
    }

    private func storeNewReceipt() throws -> String? {
        guard let data = receipt.pendingImage else { return nil }
        return try dependencies.receipts.save(data)
    }

    /// A sentence for the error alert.
    func message(for error: any Error) -> String {
        if case DataError.invalidExpense = error {
            return String(localized: "This expense does not add up. Check the amounts and try again.")
        }
        return String(localized: "The expense could not be saved. Try again.")
    }

    /// Looks for an existing expense that matches the one being added, to warn before saving.
    func refreshDuplicates() {
        guard case .add = mode, let expense = makeExpense() else {
            possibleDuplicates = []
            return
        }
        possibleDuplicates = (try? services.expenses.duplicates(of: expense, withinDays: 3)) ?? []
    }
}
