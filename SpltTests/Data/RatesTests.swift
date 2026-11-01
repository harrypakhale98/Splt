import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Rates provider")
struct FrankfurterProviderTests {
    private let when = Date(timeIntervalSince1970: 1_750_000_000)
    private let json = #"{"amount":1.0,"base":"USD","date":"2026-03-02","rates":{"EUR":0.9231,"JPY":151.2,"GBP":0.7893}}"#

    private func provider(host: String, reply: @escaping @Sendable (URLRequest) -> StubURLProtocol.Reply) -> FrankfurterRatesProvider {
        StubURLProtocol.register(host: host, reply)
        return FrankfurterRatesProvider(
            session: StubURLProtocol.session(), baseURL: URL(string: "https://\(host)/v1")!, now: { when }
        )
    }

    @Test func decodesAResponseExactly() throws {
        let decoded = try #require(FrankfurterRatesProvider.decode(Data(json.utf8), expectedBase: "usd", fetchedAt: when))
        #expect(decoded.base == "USD")
        #expect(decoded.day == "2026-03-02")
        #expect(decoded.rates["EUR"] == Decimal(string: "0.9231"))
        #expect(decoded.rates["JPY"] == Decimal(string: "151.2"))
        #expect(decoded.rates.count == 3)
        #expect(decoded.fetchedAt == when)
    }

    @Test(arguments: [
        #"{"base":"EUR","date":"2026-03-02","rates":{"USD":1.1}}"#,
        #"{"base":"USD","date":"yesterday","rates":{"EUR":0.9}}"#,
        #"{"base":"USD","date":"2026-03-02","rates":{}}"#,
        #"{"base":"USD","date":"2026-03-02","rates":{"EUR":-0.9}}"#,
        #"{"base":"USD","date":"2026-03-02","rates":{"EUR":0}}"#,
        #"{"base":"USD","date":"2026-03-02","rates":{"EURO":0.9}}"#,
        #"{"base":"USD","date":"2026-03-02"}"#,
        #"{"base":"USD","date":"2026-03-02","rates":{"EUR":"0.9"}}"#,
        #"<html>captive portal</html>"#,
        ""
    ])
    func rejectsAnythingThatIsNotARatesResponse(body: String) {
        #expect(FrankfurterRatesProvider.decode(Data(body.utf8), expectedBase: "USD", fetchedAt: when) == nil)
    }

    @Test func requestsTheLatestTableForABase() async throws {
        let host = "latest-\(UUID().uuidString).test"
        let body = json
        let provider = provider(host: host) { _ in .init(body: Data(body.utf8)) }
        let result = try #require(await provider.latest(base: "usd"))
        #expect(result.rates["EUR"] == Decimal(string: "0.9231"))
        let url = try #require(StubURLProtocol.requests(host: host).first)
        #expect(url.path == "/v1/latest")
        #expect(url.query == "base=USD")
    }

    @Test func requestsAHistoricalDay() async throws {
        let host = "history-\(UUID().uuidString).test"
        let body = json
        let provider = provider(host: host) { _ in .init(body: Data(body.utf8)) }
        #expect(await provider.historical(base: "USD", on: "2026-03-02") != nil)
        let url = try #require(StubURLProtocol.requests(host: host).first)
        #expect(url.path == "/v1/2026-03-02")
        #expect(url.query == "base=USD")
    }

    @Test func failuresReturnNilInsteadOfThrowing() async {
        let host = "failing-\(UUID().uuidString).test"
        let status = Mutex500()
        let provider = provider(host: host) { _ in
            status.next()
        }
        #expect(await provider.latest(base: "USD") == nil)
        #expect(await provider.latest(base: "USD") == nil)
        #expect(await provider.latest(base: "USD") == nil)
    }

    @Test func badInputNeverReachesTheNetwork() async {
        let host = "bad-\(UUID().uuidString).test"
        let provider = provider(host: host) { _ in .init() }
        #expect(await provider.latest(base: "US") == nil)
        #expect(await provider.latest(base: "../x") == nil)
        #expect(await provider.historical(base: "USD", on: "2026-3-2") == nil)
        #expect(await provider.historical(base: "USD", on: "latest") == nil)
        #expect(StubURLProtocol.requests(host: host).isEmpty)
    }

    @Test func theDefaultSessionHasShortTimeouts() {
        let configuration = FrankfurterRatesProvider.makeSession().configuration
        #expect(configuration.timeoutIntervalForRequest <= 10)
        #expect(!configuration.waitsForConnectivity)
    }

    @Test func tablesSurviveAJSONRoundTripExactly() throws {
        let original = RateTable(base: "usd", day: "2026-03-02", rates: ["EUR": Decimal(string: "0.923145")!], fetchedAt: when)
        let decoded = try JSONDecoder().decode(RateTable.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}

/// Cycles through a server error, a dropped connection and garbage.
private final class Mutex500: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> StubURLProtocol.Reply {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        switch count % 3 {
        case 0: return .init(status: 200, body: Data("not json".utf8))
        case 1: return .init(status: 500)
        default: return .init(error: URLError(.notConnectedToInternet))
        }
    }
}

@Suite("Rates cache")
struct RatesCacheTests {
    private let start = Date(timeIntervalSince1970: 1_750_000_000)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rates-\(UUID().uuidString)")
    }

    private func clock() -> (reading: @Sendable () -> Date, TestClock) {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_750_000_000))
        return (clock.reading, clock)
    }

    @Test func latestIsFreshForTwelveHoursThenStaleButReadable() async {
        let (reading, clock) = clock()
        let cache = RatesCache(directory: nil, now: reading)
        await cache.storeLatest(table("USD", fetchedAt: clock.start, rates: ["EUR": 0.9]))
        #expect(await cache.latest(base: "USD")?.isFresh == true)
        clock.advance(by: 11 * 3600)
        #expect(await cache.latest(base: "USD")?.isFresh == true)
        clock.advance(by: 2 * 3600)
        let stale = await cache.latest(base: "usd")
        #expect(stale?.isFresh == false)
        #expect(stale?.table.rates["EUR"] == 0.9)
    }

    @Test func unknownBasesAreMisses() async {
        let cache = RatesCache(directory: nil)
        #expect(await cache.latest(base: "USD") == nil)
        #expect(await cache.historical(base: "USD", day: "2026-03-02") == nil)
    }

    @Test func historicalRatesNeverExpire() async {
        let (reading, clock) = clock()
        let cache = RatesCache(directory: nil, now: reading)
        await cache.storeHistorical(table("USD", fetchedAt: clock.start, rates: ["EUR": 0.9]), day: "2026-03-02")
        clock.advance(by: 10 * 365 * 86_400)
        #expect(await cache.historical(base: "USD", day: "2026-03-02")?.rates["EUR"] == 0.9)
        #expect(await cache.historical(base: "USD", day: "2026-03-03") == nil)
        #expect(await cache.historical(base: "EUR", day: "2026-03-02") == nil)
    }

    @Test func tablesPersistAcrossInstances() async {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = RatesCache(directory: folder)
        await first.storeLatest(table("USD", fetchedAt: Date(), rates: ["EUR": Decimal(string: "0.9231")!]))
        await first.storeHistorical(table("USD", fetchedAt: Date(), rates: ["JPY": 150]), day: "2026-01-05")

        let second = RatesCache(directory: folder)
        #expect(await second.latest(base: "USD")?.table.rates["EUR"] == Decimal(string: "0.9231"))
        #expect(await second.historical(base: "USD", day: "2026-01-05")?.rates["JPY"] == 150)
    }

    @Test func aDamagedFileReadsAsEmptyAndIsRepaired() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: folder.appendingPathComponent("rates.json"))
        let cache = RatesCache(directory: folder)
        #expect(await cache.latest(base: "USD") == nil)
        await cache.storeLatest(table("USD", fetchedAt: Date(), rates: ["EUR": 0.9]))
        #expect(await RatesCache(directory: folder).latest(base: "USD") != nil)
    }

    @Test func anUnwritableLocationDoesNotBreakTheMemoryLayer() async {
        let cache = RatesCache(directory: URL(fileURLWithPath: "/dev/null/nowhere"))
        await cache.storeLatest(table("USD", fetchedAt: Date(), rates: ["EUR": 0.9]))
        #expect(await cache.latest(base: "USD") != nil)
    }

    @Test func theHistoricalLayerKeepsToItsLimitByDroppingTheOldest() async {
        let cache = RatesCache(directory: nil)
        let limit = RatesCache.historicalLimit
        for index in 0..<(limit + 5) {
            let day = String(format: "2025-%02d-%02d", index / 28 % 12 + 1, index % 28 + 1) + "#\(index)"
            await cache.storeHistorical(
                table("USD", fetchedAt: Date(timeIntervalSince1970: TimeInterval(index)), rates: ["EUR": 1]), day: day
            )
        }
        #expect(await cache.historical(base: "USD", day: "2025-01-01#0") == nil)
        let last = limit + 4
        let newest = String(format: "2025-%02d-%02d", last / 28 % 12 + 1, last % 28 + 1) + "#\(last)"
        #expect(await cache.historical(base: "USD", day: newest) != nil)
    }
}

@Suite("Rates service")
struct RatesServiceTests {
    private let clock = TestClock(start: Date(timeIntervalSince1970: 1_750_000_000))
    private let provider = StubRatesProvider()

    private func service(cache: RatesCache? = nil) -> RatesService {
        RatesService(provider: provider, cache: cache ?? RatesCache(directory: nil, now: clock.reading), now: clock.reading)
    }

    private func group(currency: String = "USD", pinned: PinnedRate? = nil) -> SplitGroup {
        SplitGroup(name: "Trip", currencyCode: currency, pinnedRate: pinned)
    }

    private func latestTable(_ eur: Decimal) -> RateTable {
        table("USD", day: "2026-03-02", fetchedAt: clock.start, rates: ["EUR": eur])
    }

    @Test func aFreshCachedTableIsUsedWithoutAskingTheProvider() async {
        let service = service()
        provider.setLatest(latestTable(0.9), base: "USD")
        #expect(await service.latestTable(base: "USD")?.rates["EUR"] == 0.9)
        provider.setLatest(latestTable(0.8), base: "USD")
        #expect(await service.latestTable(base: "usd")?.rates["EUR"] == 0.9)
        #expect(provider.latestCalls == 1)
    }

    @Test func aStaleTableIsRefreshedAfterTwelveHours() async {
        let service = service()
        provider.setLatest(latestTable(0.9), base: "USD")
        _ = await service.latestTable(base: "USD")
        clock.advance(by: 13 * 3600)
        provider.setLatest(table("USD", fetchedAt: clock.start.addingTimeInterval(13 * 3600), rates: ["EUR": 0.8]), base: "USD")
        #expect(await service.latestTable(base: "USD")?.rates["EUR"] == 0.8)
        #expect(provider.latestCalls == 2)
    }

    @Test func offlineFallsBackToTheStaleTable() async {
        let service = service()
        provider.setLatest(latestTable(0.9), base: "USD")
        _ = await service.latestTable(base: "USD")
        clock.advance(by: 30 * 3600)
        provider.setLatest(nil, base: "USD")
        #expect(await service.latestTable(base: "USD")?.rates["EUR"] == 0.9)
    }

    @Test func offlineWithNothingCachedIsNil() async {
        let service = service()
        #expect(await service.latestTable(base: "USD") == nil)
        #expect(await service.historicalTable(base: "USD", on: clock.start) == nil)
    }

    @Test func aFailedLookupIsNotRetriedStraightAway() async {
        let service = service()
        _ = await service.latestTable(base: "USD")
        _ = await service.latestTable(base: "USD")
        #expect(provider.latestCalls == 1)
        clock.advance(by: RatesService.retryDelay + 1)
        _ = await service.latestTable(base: "USD")
        #expect(provider.latestCalls == 2)
    }

    @Test func aTableThatLoadsLaterIsPickedUpAfterTheRetryDelay() async {
        let service = service()
        #expect(await service.latestTable(base: "USD") == nil)
        provider.setLatest(latestTable(0.9), base: "USD")
        clock.advance(by: RatesService.retryDelay + 1)
        #expect(await service.latestTable(base: "USD")?.rates["EUR"] == 0.9)
    }

    @Test func aRestartReadsTheCachedTableOffline() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        provider.setLatest(latestTable(0.9), base: "USD")
        _ = await service(cache: RatesCache(directory: folder, now: clock.reading)).latestTable(base: "USD")

        let offline = StubRatesProvider()
        let restarted = RatesService(provider: offline, cache: RatesCache(directory: folder, now: clock.reading), now: clock.reading)
        #expect(await restarted.latestTable(base: "USD")?.rates["EUR"] == 0.9)
        #expect(offline.latestCalls == 0)
    }

    @Test func historicalTablesAreCachedForever() async {
        let service = service()
        let past = clock.start.addingTimeInterval(-20 * 86_400)
        let day = RatesService.dayString(past, timeZone: .current)
        provider.setHistorical(table("USD", day: day, fetchedAt: clock.start, rates: ["EUR": 0.85]), base: "USD", day: day)
        #expect(await service.historicalTable(base: "USD", on: past)?.rates["EUR"] == 0.85)
        provider.setHistorical(nil, base: "USD", day: day)
        clock.advance(by: 400 * 86_400)
        #expect(await service.historicalTable(base: "USD", on: past)?.rates["EUR"] == 0.85)
        #expect(provider.historicalCalls == 1)
    }

    // Precedence: pinned, then the expense day, then latest, then nothing.

    @Test func aPinnedRateForTheExpensePairWinsWithoutAnyLookup() async throws {
        let service = service()
        provider.setLatest(latestTable(0.9), base: "USD")
        let pinned = PinnedRate(from: "EUR", to: "USD", rate: Decimal(string: "1.25")!)
        let rates = try #require(await service.exchangeRates(for: group(pinned: pinned), from: "EUR"))
        #expect(rates.rate(from: "EUR", to: "USD") == Decimal(string: "1.25"))
        #expect(provider.latestCalls == 0)
        #expect(provider.historicalCalls == 0)
    }

    @Test func aPinnedRateBeatsTheTableForItsPairButOtherPairsUseTheTable() async throws {
        let service = service()
        provider.setLatest(table("USD", fetchedAt: clock.start, rates: ["EUR": 0.9, "JPY": 150]), base: "USD")
        let pinned = PinnedRate(from: "EUR", to: "USD", rate: Decimal(string: "1.25")!)
        let rates = try #require(await service.exchangeRates(for: group(pinned: pinned)))
        #expect(rates.rate(from: "EUR", to: "USD") == Decimal(string: "1.25"))
        #expect(rates.rate(from: "JPY", to: "USD") == Decimal(1) / 150)
    }

    @Test func aPastExpenseDayUsesThatDaysRate() async throws {
        let service = service()
        let past = clock.start.addingTimeInterval(-10 * 86_400)
        let day = RatesService.dayString(past, timeZone: .current)
        provider.setLatest(table("USD", fetchedAt: clock.start, rates: ["EUR": 0.9]), base: "USD")
        provider.setHistorical(table("USD", day: day, fetchedAt: clock.start, rates: ["EUR": 0.8]), base: "USD", day: day)
        let rates = try #require(await service.exchangeRates(for: group(), on: past, from: "EUR"))
        #expect(rates.rate(from: "USD", to: "EUR") == 0.8)
    }

    @Test func aMissingHistoricalDayFallsBackToTheLatestTable() async throws {
        let service = service()
        let past = clock.start.addingTimeInterval(-10 * 86_400)
        provider.setLatest(table("USD", fetchedAt: clock.start, rates: ["EUR": 0.9]), base: "USD")
        let rates = try #require(await service.exchangeRates(for: group(), on: past, from: "EUR"))
        #expect(rates.rate(from: "USD", to: "EUR") == 0.9)
    }

    @Test func todayAndFutureDatesUseTheLatestTable() async throws {
        let service = service()
        provider.setLatest(table("USD", fetchedAt: clock.start, rates: ["EUR": 0.9]), base: "USD")
        let rates = try #require(await service.exchangeRates(for: group(), on: clock.start, from: "EUR"))
        #expect(rates.rate(from: "USD", to: "EUR") == 0.9)
        #expect(provider.historicalCalls == 0)
        #expect(await service.exchangeRates(for: group(), on: clock.start.addingTimeInterval(5 * 86_400)) != nil)
        #expect(provider.historicalCalls == 0)
    }

    @Test func withNothingKnownThereIsNoConversion() async {
        let service = service()
        #expect(await service.exchangeRates(for: group(), on: clock.start.addingTimeInterval(-86_400 * 3), from: "EUR") == nil)
    }

    @Test func aPinnedRateAloneStillConvertsWhenOffline() async throws {
        let service = service()
        let pinned = PinnedRate(from: "EUR", to: "USD", rate: Decimal(string: "1.25")!)
        let rates = try #require(await service.exchangeRates(for: group(pinned: pinned), from: "JPY"))
        #expect(rates.rate(from: "EUR", to: "USD") == Decimal(string: "1.25"))
        #expect(rates.rate(from: "JPY", to: "USD") == nil)
    }

    @Test func conversionsUseTheChosenTable() async throws {
        let service = service()
        provider.setLatest(table("USD", fetchedAt: clock.start, rates: ["EUR": 0.9]), base: "USD")
        let rates = try #require(await service.exchangeRates(for: group(), from: "EUR"))
        let euros = Money(minorUnits: 9000, currencyCode: "EUR")
        #expect(try rates.convert(euros, to: "USD") == usdAmount(10_000))
    }
}

@MainActor
@Suite("Expense rates seam")
struct ExpenseRatesSeamTests {
    private let clock = TestClock(start: Date(timeIntervalSince1970: 1_750_000_000))

    private func group(pinned: PinnedRate? = nil) -> SplitGroup {
        SplitGroup(name: "Trip", currencyCode: "USD", pinnedRate: pinned)
    }

    @Test func theSeamStartsEmptyThenAnswersOnceWarmed() async throws {
        let provider = StubRatesProvider()
        provider.setLatest(table("USD", fetchedAt: clock.start, rates: ["EUR": 0.9]), base: "USD")
        let service = RatesService(provider: provider, cache: RatesCache(directory: nil, now: clock.reading), now: clock.reading)
        let seam = ExpenseRates.cached(by: service)
        #expect(seam.rates(group()) == nil)
        await service.warmUp(currencies: ["USD"])
        let rates = try #require(seam.rates(group()))
        #expect(rates.rate(from: "EUR", to: "USD") == Decimal(1) / Decimal(string: "0.9")!)
    }

    @Test func thePinnedRateWinsInsideTheSeam() async throws {
        let provider = StubRatesProvider()
        provider.setLatest(table("USD", fetchedAt: clock.start, rates: ["EUR": 0.9]), base: "USD")
        let service = RatesService(provider: provider, cache: RatesCache(directory: nil, now: clock.reading), now: clock.reading)
        await service.warmUp(currencies: ["USD"])
        let pinned = PinnedRate(from: "EUR", to: "USD", rate: Decimal(string: "1.3")!)
        let rates = try #require(ExpenseRates.cached(by: service).rates(group(pinned: pinned)))
        #expect(rates.rate(from: "EUR", to: "USD") == Decimal(string: "1.3"))
    }

    @Test func aPinnedRateWorksInTheSeamBeforeAnythingIsLoaded() throws {
        let service = RatesService.offline()
        let pinned = PinnedRate(from: "EUR", to: "USD", rate: Decimal(string: "1.3")!)
        let rates = try #require(ExpenseRates.cached(by: service).rates(group(pinned: pinned)))
        #expect(rates.rate(from: "EUR", to: "USD") == Decimal(string: "1.3"))
    }

    @Test func dataServicesExposeTheSeamAndWarmItself() async throws {
        let provider = StubRatesProvider()
        provider.setLatest(table("USD", fetchedAt: clock.start, rates: ["EUR": 0.9]), base: "USD")
        let service = RatesService(provider: provider, cache: RatesCache(directory: nil, now: clock.reading), now: clock.reading)
        let services = try DataServices.inMemory(rates: service, now: clock.reading)
        try services.groups.create(SplitGroup(name: "Flat", currencyCode: "USD"))
        await services.warmRates()
        let seamGroup = try #require(try services.groups.groups(includeArchived: false).first)
        #expect(services.expenseRates.rates(seamGroup) != nil)
        #expect(services.rates === service)
    }

    @Test func inMemoryServicesStayOffline() throws {
        let services = try DataServices.inMemory()
        #expect(services.expenseRates.rates(group()) == nil)
    }
}
