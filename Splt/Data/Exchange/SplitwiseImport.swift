import SpltCore

struct ImportWarning: Hashable, Sendable {
    /// The line in the file, counting the header as line 1.
    var line: Int
    var message: String
}

/// What a Splitwise CSV file contains once read.
struct SplitwiseImport: Sendable {
    /// Member names in column order.
    var memberNames: [String]
    /// The person for each member name. Names that matched a known person reuse their id.
    var members: [String: PersonID]
    var expenses: [Expense]
    var payments: [Payment]
    var warnings: [ImportWarning]
}
