import Foundation
import SpltCore

/// Who paid the bill, as far as the note says.
enum QuickAddPayer: Equatable, Sendable {
    case me
    case person(String)
}

/// A named person with an amount in minor units.
struct QuickAddShare: Equatable, Sendable {
    var name: String
    var amount: Money
}

/// How the note says the cost should be divided.
enum QuickAddSplitHint: Equatable, Sendable {
    /// Everyone pays the same.
    case equal
    /// Split equally, then move these signed amounts (negative means owes less).
    case adjustments([QuickAddShare])
    /// These people owe exactly these amounts.
    case exactAmounts([QuickAddShare])
}

/// What a typed or spoken note turned into. Every field is optional because notes are short;
/// the form shows what was understood and the person fixes the rest.
struct QuickAddDraft: Equatable, Sendable {
    enum Source: Sendable {
        case rules
        case model
    }

    var title: String = ""
    /// Minor units in `currencyHint`, or in the default currency when no currency was written.
    var amount: Money?
    /// An ISO code, only when the note mentioned a currency.
    var currencyHint: String?
    /// Other people on the expense, spelled as in the candidate list when they match one.
    var participantNames: [String] = []
    var payer: QuickAddPayer?
    var splitHint: QuickAddSplitHint?
    var category: ExpenseCategoryHint?
    var source: Source = .rules

    var payerName: String? {
        if case .person(let name) = payer { return name }
        return nil
    }

    var isEmpty: Bool {
        title.isEmpty && amount == nil && participantNames.isEmpty && payer == nil && splitHint == nil
    }
}

/// What the parser knows about the group the expense is being added to.
struct QuickAddContext: Sendable {
    /// Members of the group other than the person typing.
    var candidateNames: [String]
    var defaultCurrencyCode: String
    /// The year the note is written in. A number that could be this year is less likely to be the price.
    var year: Int

    init(
        candidateNames: [String] = [], defaultCurrencyCode: String = "USD",
        year: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) {
        self.candidateNames = candidateNames
        self.defaultCurrencyCode = defaultCurrencyCode
        self.year = year
    }
}

/// Reads a short note such as "dinner 60 with Sam and Priya, I paid" into a draft.
protocol QuickAddParsing: Sendable {
    func parse(_ text: String, context: QuickAddContext) async -> QuickAddDraft
}
