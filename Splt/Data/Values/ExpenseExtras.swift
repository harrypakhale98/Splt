import Foundation
import SpltCore

struct ExpenseLocation: Hashable, Sendable, Codable {
    var name: String?
    var latitude: Double
    var longitude: Double

    init(name: String? = nil, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// What an expense carries beyond `SpltCore.Expense`.
struct ExpenseExtras: Hashable, Sendable {
    /// A file in the app's receipt folder, not a path.
    var receiptFileName: String?
    var location: ExpenseLocation?
    var recurrence: RecurrenceRule?
    /// The recurring template that created the expense.
    var recurringExpenseID: UUID?

    init(
        receiptFileName: String? = nil,
        location: ExpenseLocation? = nil,
        recurrence: RecurrenceRule? = nil,
        recurringExpenseID: UUID? = nil
    ) {
        self.receiptFileName = receiptFileName
        self.location = location
        self.recurrence = recurrence
        self.recurringExpenseID = recurringExpenseID
    }
}
