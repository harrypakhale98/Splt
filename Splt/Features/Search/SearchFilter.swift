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
    /// The currency the amounts were written in, when the question named one, as in "over 50 EUR".
    var amountCurrency: String?

    /// How amounts in different currencies are put side by side for "over" and "under".
    struct AmountScale: Sendable {
        /// The currency the bounds are in.
        var currency: String
        /// What one unit of each currency is worth in a common base, from the rates the app holds. Empty without rates.
        var unitValues: [String: Double] = [:]

        /// The amount's size in `currency`, or nil when there is no fair way to compare it:
        /// 600 yen is not "over 500" dollars, so without a rate only the same currency counts.
        func size(of money: Money) -> Decimal? {
            let magnitude = money.decimalValue.magnitude
            let code = money.currencyCode.uppercased()
            let target = currency.uppercased()
            if code == target { return magnitude }
            guard let from = unitValues[code], let to = unitValues[target], from > 0, to > 0 else { return nil }
            return magnitude * Decimal(from / to)
        }
    }

    /// True when the question said more than plain words, such as who paid or when.
    var isStructured: Bool {
        category != nil || payer != nil || participant != nil || period != nil || minAmount != nil || maxAmount != nil
    }

    /// - Parameter scale: how to compare amounts; without one, an amount is compared in its own currency,
    ///   or only with expenses in the currency the question named.
    func matches(
        _ expense: Expense, groupName: String?, names: [PersonID: String], scale: AmountScale? = nil, locale: Locale = .current
    ) -> Bool {
        if let payer, expense.payers[payer] == nil { return false }
        if let participant, !expense.participants.contains(participant) { return false }
        if let period, !period.contains(expense.date) { return false }
        if minAmount != nil || maxAmount != nil {
            let scale = scale ?? AmountScale(currency: amountCurrency ?? expense.total.currencyCode)
            guard let size = scale.size(of: expense.total) else { return false }
            if let minAmount, size < minAmount { return false }
            if let maxAmount, size > maxAmount { return false }
        }
        let haystack = Self.haystack(expense, groupName: groupName, names: names, locale: locale)
        if let category {
            let word = categoryWord
            let inCategory = expense.category == category
            let inText = word.map { Self.contains(haystack, $0) } ?? false
            if !inCategory && !inText { return false }
        }
        return terms.allSatisfy { Self.contains(haystack, $0) }
    }

    private static func haystack(_ expense: Expense, groupName: String?, names: [PersonID: String], locale: Locale) -> String {
        let people = expense.participants.compactMap { names[$0] }.joined(separator: " ")
        // both "42.50" and the way the person writes it, such as "42,50" in German
        let plain = expense.total.plainString(locale: Locale(identifier: "en_US_POSIX"))
        let mark = locale.decimalSeparator ?? "."
        let own = mark == "." ? "" : plain.replacingOccurrences(of: ".", with: mark)
        return [expense.title, expense.note, expense.category.rawValue, groupName ?? "", people, plain, own].joined(separator: " ")
    }

    private static func contains(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
