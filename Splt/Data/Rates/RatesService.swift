import Foundation
import SpltCore
import Synchronization

/// Finds exchange rates for a group, from the best source available.
///
/// Order: the group's pinned rate for its own pair, then the rate published for the expense's
/// day, then the latest table, then nothing. Nothing here throws or blocks the UI: a failed
/// lookup returns nil, and a stale cached table still answers while offline.
final class RatesService: Sendable {
    /// After a failed fetch the same lookup is not retried for this long.
    static let retryDelay: TimeInterval = 300

    let snapshot = RatesSnapshot()

    private let provider: any RatesProvider
    private let cache: RatesCache
    private let now: @Sendable () -> Date
    private let failures = Mutex<[String: Date]>([:])

    init(provider: any RatesProvider, cache: RatesCache, now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.cache = cache
        self.now = now
    }

    /// Frankfurter rates cached in Application Support.
    static func live() -> RatesService {
        RatesService(provider: FrankfurterRatesProvider(), cache: .standard())
    }

    /// A service with no network and no files, for tests, previews and offline builds.
    static func offline() -> RatesService {
        RatesService(provider: NoRatesProvider(), cache: RatesCache(directory: nil))
    }

    /// The latest table: a fresh cached one, else a new download, else a stale cached one.
    func latestTable(base: String) async -> RateTable? {
        let base = base.uppercased()
        let cached = await cache.latest(base: base)
        if let cached, cached.isFresh {
            snapshot.store(cached.table)
            return cached.table
        }
        let key = "latest|" + base
        if !recentlyFailed(key) {
            if let fetched = await provider.latest(base: base) {
                await cache.storeLatest(fetched)
                snapshot.store(fetched)
                return fetched
            }
            markFailed(key)
        }
        if let cached {
            snapshot.store(cached.table)
            return cached.table
        }
        return nil
    }

    /// The table published for the calendar day of `date`. Past days never change, so a cached one is final.
    ///
    /// The provider answers with the last day it has. For a recent day that can mean its rates are
    /// not out yet, so an earlier table is used but not kept. For a weekend or holiday the earlier
    /// table is the right one for good, which is taken as settled once the day is more than two days back.
    func historicalTable(base: String, on date: Date, timeZone: TimeZone = .current) async -> RateTable? {
        let base = base.uppercased()
        let day = Self.dayString(date, timeZone: timeZone)
        if let cached = await cache.historical(base: base, day: day) { return cached }
        let key = "\(base)|\(day)"
        guard !recentlyFailed(key) else { return nil }
        guard let fetched = await provider.historical(base: base, on: day) else {
            markFailed(key)
            return nil
        }
        if fetched.day == day || isMoreThanTwoDaysAgo(day, timeZone: timeZone) {
            await cache.storeHistorical(fetched, day: day)
        }
        return fetched
    }

    private func isMoreThanTwoDaysAgo(_ day: String, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let cutoff = calendar.date(byAdding: .day, value: -2, to: now()) else { return false }
        return day < Self.dayString(cutoff, timeZone: timeZone)
    }

    /// Rates for converting into the group's currency.
    ///
    /// - Parameters:
    ///   - date: the expense date. A past day uses that day's rates, today or later uses the latest.
    ///   - currencyCode: the expense currency. When the group's pinned rate covers that pair, no lookup happens.
    func exchangeRates(
        for group: SplitGroup, on date: Date? = nil, from currencyCode: String? = nil, timeZone: TimeZone = .current
    ) async -> ExchangeRates? {
        let pinned = group.pinnedRate
        if let currencyCode, let pinned, Self.covers(pinned, currencyCode, group.currencyCode) {
            return Self.exchangeRates(table: nil, pinned: pinned)
        }
        var table: RateTable?
        if let date, Self.dayString(date, timeZone: timeZone) < Self.dayString(now(), timeZone: timeZone) {
            table = await historicalTable(base: group.currencyCode, on: date, timeZone: timeZone)
        }
        if table == nil {
            table = await latestTable(base: group.currencyCode)
        }
        return Self.exchangeRates(table: table, pinned: pinned)
    }

    /// Loads or downloads the latest tables so the snapshot can answer right away.
    func warmUp(currencies: Set<String>) async {
        for code in currencies.sorted() {
            _ = await latestTable(base: code)
        }
    }

    static func exchangeRates(table: RateTable?, pinned: PinnedRate?) -> ExchangeRates? {
        let pins = pinned.map { [$0] } ?? []
        if let table {
            return ExchangeRates(baseCurrency: table.base, rates: table.rates, pinned: pins, asOf: table.fetchedAt)
        }
        guard let pinned else { return nil }
        return ExchangeRates(baseCurrency: pinned.from, rates: [pinned.to: pinned.rate], pinned: pins)
    }

    static func dayString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func covers(_ pinned: PinnedRate, _ first: String, _ second: String) -> Bool {
        let a = first.uppercased()
        let b = second.uppercased()
        return (pinned.from == a && pinned.to == b) || (pinned.from == b && pinned.to == a)
    }

    private func recentlyFailed(_ key: String) -> Bool {
        failures.withLock { failed in
            guard let at = failed[key] else { return false }
            return now().timeIntervalSince(at) < Self.retryDelay
        }
    }

    private func markFailed(_ key: String) {
        failures.withLock { $0[key] = now() }
    }
}
