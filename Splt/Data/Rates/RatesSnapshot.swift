import Foundation
import SpltCore
import Synchronization

/// The latest tables the app already holds, readable without waiting. Forms that need an answer
/// on the spot read this; the service fills it in the background.
final class RatesSnapshot: Sendable {
    private let tables = Mutex<[String: RateTable]>([:])

    func store(_ table: RateTable) {
        tables.withLock { $0[table.base] = table }
    }

    /// What one unit of each currency is worth in the base of a held table, for ranking amounts across currencies.
    /// Empty until a table has been loaded.
    func unitValues() -> [String: Double] {
        guard let table = tables.withLock({ $0.values.sorted { $0.base < $1.base }.first }) else { return [:] }
        var values = [table.base: 1.0]
        for (code, rate) in table.rates {
            let perBase = NSDecimalNumber(decimal: rate).doubleValue
            if perBase > 0 { values[code] = 1 / perBase }
        }
        return values
    }

    /// Rates for a group: its pinned rate wins for its own currency pair, and any held table
    /// answers the other pairs. Nil when the group has neither.
    func exchangeRates(for group: SplitGroup) -> ExchangeRates? {
        let table = tables.withLock { held in held[group.currencyCode] ?? held.values.sorted { $0.base < $1.base }.first }
        return RatesService.exchangeRates(table: table, pinned: group.pinnedRate)
    }
}
