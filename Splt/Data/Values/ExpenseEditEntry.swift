import Foundation
import SpltCore

enum ExpenseField: String, Hashable, Sendable, Codable, CaseIterable {
    case title
    case total
    case date
    case category
    case payers
    case split
    case note
    case group
    case receipt
    case location
    case recurrence
}

/// One edit in an expense's history.
struct ExpenseEditEntry: Hashable, Sendable, Codable, Identifiable {
    var id: UUID
    var date: Date
    var editor: PersonID?
    var changedFields: [ExpenseField]
    /// The values before the edit, kept for the two fields people look for first.
    var previousTitle: String?
    var previousTotal: Money?

    init(
        id: UUID = UUID(),
        date: Date,
        editor: PersonID? = nil,
        changedFields: [ExpenseField],
        previousTitle: String? = nil,
        previousTotal: Money? = nil
    ) {
        self.id = id
        self.date = date
        self.editor = editor
        self.changedFields = changedFields
        self.previousTitle = previousTitle
        self.previousTotal = previousTotal
    }
}

/// Everything stored about an expense that `SpltCore.Expense` does not model.
struct ExpenseDetails: Hashable, Sendable {
    var extras: ExpenseExtras
    var history: [ExpenseEditEntry]
    var createdAt: Date
    var createdBy: PersonID?
    var modifiedAt: Date
}
