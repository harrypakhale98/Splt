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

    /// Rates for a group: its pinned rate wins for its own currency pair, and any held table
    /// answers the other pairs. Nil when the group has neither.
    func exchangeRates(for group: SplitGroup) -> ExchangeRates? {
        let table = tables.withLock { held in held[group.currencyCode] ?? held.values.sorted { $0.base < $1.base }.first }
        return RatesService.exchangeRates(table: table, pinned: group.pinnedRate)
    }
}
