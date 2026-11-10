import Foundation
import SpltCore

/// What a typed question asks for, once it has been read into parts.
struct SearchFilter: Equatable, Sendable {
    /// Words that must appear in the title, note, category, group or the names of the people involved.
    var terms: [String] = []
    var category: ExpenseCategory?
    /// The word that named the category, so an expense with that word in its title still matches.
    var categoryWord: String?
    var payer: PersonID?
    var participant: PersonID?
    var period: Range<Date>?
    /// Amounts in major units, for example 50 for fifty dollars.
    var minAmount: Decimal?
    var maxAmount: Decimal?

    /// True when the question said more than plain words, such as who paid or when.
    var isStructured: Bool {
        category != nil || payer != nil || participant != nil || period != nil || minAmount != nil || maxAmount != nil
    }

    func matches(_ expense: Expense, groupName: String?, names: [PersonID: String]) -> Bool {
        if let payer, expense.payers[payer] == nil { return false }
        if let participant, !expense.participants.contains(participant) { return false }
        if let period, !period.contains(expense.date) { return false }
        let size = expense.total.decimalValue.magnitude
        if let minAmount, size < minAmount { return false }
        if let maxAmount, size > maxAmount { return false }
        let haystack = Self.haystack(expense, groupName: groupName, names: names)
        if let category {
            let word = categoryWord
            let inCategory = expense.category == category
            let inText = word.map { Self.contains(haystack, $0) } ?? false
            if !inCategory && !inText { return false }
        }
        return terms.allSatisfy { Self.contains(haystack, $0) }
    }

    private static func haystack(_ expense: Expense, groupName: String?, names: [PersonID: String]) -> String {
        let people = expense.participants.compactMap { names[$0] }.joined(separator: " ")
        let amount = expense.total.plainString(locale: Locale(identifier: "en_US_POSIX"))
        return [expense.title, expense.note, expense.category.rawValue, groupName ?? "", people, amount].joined(separator: " ")
    }

    private static func contains(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
