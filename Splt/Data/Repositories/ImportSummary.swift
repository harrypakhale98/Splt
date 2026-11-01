struct ImportSummary: Hashable, Sendable {
    var expensesAdded: Int
    var paymentsAdded: Int
    var peopleAdded: Int
    var warnings: [ImportWarning]
}
