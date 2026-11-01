import Foundation
import SpltCore

/// Why the form cannot be saved yet. `message` is shown next to the disabled Save button.
enum ExpenseFormIssue: Error, Equatable {
    case missingAmount
    case missingTitle
    case noPayer
    case payersShort(Money)
    case payersOver(Money)
    case noParticipants
    case splitShort(Money)
    case splitOver(Money)
    case percentShort(basisPoints: Int64)
    case percentOver(basisPoints: Int64)
    case negativeValue
    case noShares
    case noItems
    case itemWithoutPeople(name: String)
    case negativeShare(name: String)
    case invalidNumber
    case invalidSplit

    func message(locale: Locale = .current) -> String {
        func amount(_ money: Money) -> String { MoneyFormatting.magnitudeString(money, locale: locale) }
        func percent(_ basisPoints: Int64) -> String { AmountInput.hundredthsText(basisPoints, locale: locale) + "%" }
        switch self {
        case .missingAmount: return String(localized: "Enter an amount to save.")
        case .missingTitle: return String(localized: "Add a title to save.")
        case .noPayer: return String(localized: "Choose who paid.")
        case .payersShort(let money): return String(localized: "\(amount(money)) of the payments is still missing.")
        case .payersOver(let money): return String(localized: "The payments are \(amount(money)) too high.")
        case .noParticipants: return String(localized: "Choose who to split with.")
        case .splitShort(let money): return String(localized: "\(amount(money)) is left to assign.")
        case .splitOver(let money): return String(localized: "The split is \(amount(money)) over the total.")
        case .percentShort(let value): return String(localized: "\(percent(value)) is left to assign.")
        case .percentOver(let value): return String(localized: "The percentages are \(percent(value)) over 100%.")
        case .negativeValue: return String(localized: "Values cannot be negative.")
        case .noShares: return String(localized: "Give at least one person a share.")
        case .noItems: return String(localized: "Add at least one item.")
        case .itemWithoutPeople(let name): return String(localized: "Assign \(name) to someone.")
        case .negativeShare(let name): return String(localized: "The adjustments leave \(name) with a negative share.")
        case .invalidNumber: return String(localized: "One of the numbers is not valid.")
        case .invalidSplit: return String(localized: "This split does not add up.")
        }
    }
}
