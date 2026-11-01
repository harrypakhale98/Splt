import Foundation
import SpltCore

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
