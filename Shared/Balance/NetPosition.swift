import Foundation
import SpltCore

/// Your net position across currencies: the currency with the biggest swing leads, the rest follow.
/// The Groups and Friends heroes and the Your Balance widget all read it, so they always agree.
struct NetPosition: Equatable, Sendable {
    /// Signed net in the currency where it is largest. Nil when you are square everywhere.
    var primary: Money?
    /// Signed net in every other currency, by currency code.
    var others: [Money]

    var isSettled: Bool { primary == nil }

    /// From what you are owed and what you owe, each one positive amount per currency.
    init(owedToYou: [Money], youOwe: [Money]) {
        var net: [String: Int64] = [:]
        for amount in owedToYou { net[amount.currencyCode, default: 0] &+= amount.minorUnits }
        for amount in youOwe { net[amount.currencyCode, default: 0] &-= amount.minorUnits }
        var signed: [Money] = []
        for (code, value) in net where value != 0 {
            signed.append(Money(minorUnits: value, currencyCode: code))
        }
        signed.sort { (lhs: Money, rhs: Money) -> Bool in
            let left = lhs.minorUnits.magnitude, right = rhs.minorUnits.magnitude
            if left != right { return left > right }
            return lhs.currencyCode < rhs.currencyCode
        }
        primary = signed.first
        others = Array(signed.dropFirst()).sorted { $0.currencyCode < $1.currencyCode }
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
