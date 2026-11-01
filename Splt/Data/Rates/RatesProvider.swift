import Foundation

/// A source of exchange rates. Implementations never throw: a failure of any kind returns nil.
protocol RatesProvider: Sendable {
    func latest(base: String) async -> RateTable?
    /// The rates published for a calendar day.
    func historical(base: String, on day: String) async -> RateTable?
}

/// A provider that is never available, for tests and for builds that must stay offline.
struct NoRatesProvider: RatesProvider {
    func latest(base: String) async -> RateTable? { nil }
    func historical(base: String, on day: String) async -> RateTable? { nil }
}
