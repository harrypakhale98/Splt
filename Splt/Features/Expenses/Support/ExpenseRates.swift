import Foundation
import SpltCore

/// Where the form finds an exchange rate when an expense is in another currency than its group.
/// A pinned rate on the group always wins; a cached table can be added behind the same closure.
struct ExpenseRates: Sendable {
    var rates: @Sendable (SplitGroup) -> ExchangeRates?

    static let pinnedOnly = ExpenseRates { group in
        guard let pinned = group.pinnedRate else { return nil }
        return ExchangeRates(baseCurrency: pinned.from, rates: [pinned.to: pinned.rate], pinned: [pinned])
    }
}
