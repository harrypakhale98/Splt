import SpltCore

struct SearchResults: Hashable, Sendable {
    var expenses: [Expense]
    var people: [Person]
    var groups: [SplitGroup]

    var isEmpty: Bool { expenses.isEmpty && people.isEmpty && groups.isEmpty }
}

@MainActor
protocol SearchRepository {
    /// Finds expenses by title, note, category, amount, group name or the name of anyone who
    /// paid or owes, plus people and groups by name. Every word of the query must match.
    func search(_ query: String, limit: Int) throws -> SearchResults
}
