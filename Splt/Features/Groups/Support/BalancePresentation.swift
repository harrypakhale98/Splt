import Foundation
import SpltCore
import SwiftUI

enum BalanceDirection: Equatable, Sendable {
    case owed
    case owes
    case settled

    init(_ money: Money) {
        if money.minorUnits > 0 {
            self = .owed
        } else if money.minorUnits < 0 {
            self = .owes
        } else {
            self = .settled
        }
    }

    var caption: String {
        switch self {
        case .owed: String(localized: "you are owed")
        case .owes: String(localized: "you owe")
        case .settled: String(localized: "settled up")
        }
    }
}

/// One currency of a signed balance, ready to show.
struct BalanceLine: Identifiable, Equatable, Sendable {
    var money: Money
    var direction: BalanceDirection

    var id: String { money.currencyCode }

    /// Zero amounts are dropped, so an empty result means settled up. Sorted by currency.
    static func lines(for amounts: [Money]) -> [BalanceLine] {
        amounts
            .filter { !$0.isZero }
            .sorted { $0.currencyCode < $1.currencyCode }
            .map { BalanceLine(money: $0, direction: BalanceDirection($0)) }
    }
}

extension BalanceDirection {
    /// A short phrase to set under or beside a figure.
    var phrase: String {
        switch self {
        case .owed: String(localized: "you're owed")
        case .owes: String(localized: "you owe")
        case .settled: String(localized: "settled up")
        }
    }
}

/// An amount in the figure face with a word that says which way the money goes.
struct DirectionAmount: View {
    let money: Money
    let direction: BalanceDirection

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(MoneyFormatting.magnitudeString(money, locale: locale))
                .font(Typeface.figure)
                .foregroundStyle(direction == .owed ? Ink.owed : direction == .owes ? Ink.owe : Ink.text)
            Text(direction.phrase)
                .font(.caption)
                .foregroundStyle(Ink.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(direction.phrase) \(MoneyFormatting.magnitudeString(money, locale: locale))")
    }
}
