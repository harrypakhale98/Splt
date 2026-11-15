import Foundation
import SpltCore

/// Your net position across currencies: the currency with the biggest swing leads, the rest follow.
/// The Groups and Friends heroes and the Your Balance widget all read it, so they always agree.
struct NetPosition: Equatable, Sendable {
    /// Signed net in the currency where it is largest. Nil when you are square everywhere.
    var primary: Money?
    /// Signed net in every other currency, by currency code.
    var others: [Money]

    /// Nothing nets out, but money is still owed both ways: you owe one person what another owes you.
    var isEven = false

    var isSettled: Bool { primary == nil }

    /// What stands in for the figure when nothing nets out: "All settled up" only when nobody owes anything.
    var settledTitle: String {
        isEven ? String(localized: "You're even") : String(localized: "All settled up")
    }

    /// From what you are owed and what you owe, each one positive amount per currency. `unitValues` is what one
    /// whole unit of each currency is worth in a common one, so ¥5,000 does not lead over $40; without a value for
    /// every currency the amounts are compared as they are.
    init(owedToYou: [Money], youOwe: [Money], unitValues: [String: Double] = [:]) {
        var net: [String: Int64] = [:]
        for amount in owedToYou { net[amount.currencyCode, default: 0] &+= amount.minorUnits }
        for amount in youOwe { net[amount.currencyCode, default: 0] &-= amount.minorUnits }
        var signed: [Money] = []
        for (code, value) in net where value != 0 {
            signed.append(Money(minorUnits: value, currencyCode: code))
        }
        let weight = Self.weigher(for: signed, unitValues: unitValues)
        signed.sort { (lhs: Money, rhs: Money) -> Bool in
            let left = weight(lhs), right = weight(rhs)
            if left != right { return left > right }
            return lhs.currencyCode < rhs.currencyCode
        }
        primary = signed.first
        others = Array(signed.dropFirst()).sorted { $0.currencyCode < $1.currencyCode }
        isEven = signed.isEmpty && !(owedToYou.isEmpty && youOwe.isEmpty)
    }

    /// How big an amount is for ranking: its worth in the common currency when every amount has a rate,
    /// otherwise its size in minor units.
    static func weigher(for amounts: [Money], unitValues: [String: Double]) -> (Money) -> Double {
        let converts = !unitValues.isEmpty && amounts.allSatisfy { unitValues[$0.currencyCode] != nil }
        return { money in
            let size = Double(money.minorUnits.magnitude)
            guard converts, let value = unitValues[money.currencyCode] else { return size }
            return size / pow(10, Double(money.exponent)) * value
        }
    }

    /// The quiet sentence under the number: "You're owed €600.00 and you owe €88.15."
    static func sentence(owedToYou: [Money], youOwe: [Money], locale: Locale = .current) -> String {
        let owed = ListFormatter.localizedString(byJoining: owedToYou.map { MoneyFormatting.magnitudeString($0, locale: locale) })
        let owe = ListFormatter.localizedString(byJoining: youOwe.map { MoneyFormatting.magnitudeString($0, locale: locale) })
        switch (owedToYou.isEmpty, youOwe.isEmpty) {
        case (true, true): return String(localized: "Nobody owes anything.")
        case (false, true): return String(localized: "You're owed \(owed).")
        case (true, false): return String(localized: "You owe \(owe).")
        case (false, false): return String(localized: "You're owed \(owed) and you owe \(owe).")
        }
    }
}
