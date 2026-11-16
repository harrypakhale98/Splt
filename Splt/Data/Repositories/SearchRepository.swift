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
    /// Groups in `excludingGroups`, and their expenses, are skipped before `limit` is counted.
    func search(_ query: String, limit: Int, excludingGroups: Set<GroupID>) throws -> SearchResults
}

extension SearchRepository {
    func search(_ query: String, limit: Int) throws -> SearchResults {
        try search(query, limit: limit, excludingGroups: [])
    }
}
