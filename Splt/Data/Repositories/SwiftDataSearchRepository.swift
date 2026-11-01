import Foundation
import SpltCore
import SwiftData

@MainActor
final class SwiftDataSearchRepository: SearchRepository {
    private let env: RepositoryContext

    init(_ env: RepositoryContext) {
        self.env = env
    }

    func search(_ query: String, limit: Int) throws -> SearchResults {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return SearchResults(expenses: [], people: [], groups: []) }

        let people = try SwiftDataPersonRepository(env).allPeople()
        let groups = try env.allGroups()
        let peopleByID = Dictionary(people.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let groupNames = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        let descriptor = FetchDescriptor<ExpenseRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        var expenses: [Expense] = []
        for record in try env.context.fetch(descriptor) {
            let groupName = record.groupID.flatMap { groupNames[GroupID(rawValue: $0)] } ?? ""
            let text = [record.title, record.note, record.categoryRaw, groupName, Self.amountText(record)]
                .joined(separator: " ")
            let remaining = tokens.filter { !Self.matches(text, $0) }
            if remaining.isEmpty {
                if let expense = try? Expense(record) { expenses.append(expense) }
            } else if let expense = try? Expense(record) {
                let names = expense.participants.compactMap { peopleByID[$0] }.joined(separator: " ")
                if remaining.allSatisfy({ Self.matches(names, $0) }) { expenses.append(expense) }
            }
            if expenses.count >= limit { break }
        }
        return SearchResults(
            expenses: expenses,
            people: people.filter { person in tokens.allSatisfy { Self.matches(person.name, $0) } }.prefix(limit).map { $0 },
            groups: groups.filter { group in tokens.allSatisfy { Self.matches(group.name, $0) } }.prefix(limit).map { $0 }
        )
    }

    private static func matches(_ text: String, _ token: String) -> Bool {
        text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func amountText(_ record: ExpenseRecord) -> String {
        Money(minorUnits: record.totalMinorUnits, currencyCode: record.currencyCode)
            .plainString(locale: Locale(identifier: "en_US_POSIX"))
    }
}
