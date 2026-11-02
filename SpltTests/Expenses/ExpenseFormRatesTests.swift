import Foundation
import SpltCore
import Synchronization
import Testing
@testable import Splt

/// A rates source that answers from fixed tables and remembers what it was asked.
private final class FormRatesStub: RatesProvider {
    private struct State {
        var calls: [String] = []
        var latest: RateTable?
        var historical: [String: RateTable] = [:]
    }

    private let state = Mutex(State())

    var latestTable: RateTable? {
        get { state.withLock { $0.latest } }
        set { state.withLock { $0.latest = newValue } }
    }

    func setHistorical(_ table: RateTable, day: String) {
        state.withLock { $0.historical[day] = table }
    }

    func latest(base: String) async -> RateTable? {
        state.withLock { value in
            value.calls.append("latest")
            return value.latest
        }
    }

    func historical(base: String, on day: String) async -> RateTable? {
        state.withLock { value in
            value.calls.append("historical|\(day)")
            return value.historical[day]
        }
    }

    var log: [String] { state.withLock { $0.calls } }
}

@Suite("Expense form exchange rates")
@MainActor
struct ExpenseFormRatesTests {
    private func table(_ day: String, eur: String) -> RateTable {
        RateTable(base: "USD", day: day, rates: ["EUR": Decimal(string: eur)!], fetchedAt: Date())
    }

    private func service(_ provider: FormRatesStub) -> RatesService {
        RatesService(provider: provider, cache: RatesCache(directory: nil))
    }

    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    private func formattedDay(_ date: Date) -> String {
        RatesService.dayString(date, timeZone: .current)
    }

    @Test func theRateForTheExpenseDateIsUsed() async throws {
        let harness = try ExpenseFormHarness()
        let provider = FormRatesStub()
        let day = formattedDay(harness.fixture.clock.start)
        provider.setHistorical(table(day, eur: "0.5"), day: day)
        provider.latestTable = table("2026-11-01", eur: "0.8")
        let model = harness.newExpense(rates: service(provider))

        model.changeCurrency(to: "EUR")
        model.amountText = "100"
        await model.refreshRate()

        #expect(model.convertedTotal == usd(20_000))
        #expect(model.rateText != nil)
        #expect(!model.isFindingRate)
        #expect(provider.log.contains("historical|\(day)"))
    }

    @Test func aPinnedGroupRateBeatsEveryLookup() async throws {
        let harness = try ExpenseFormHarness()
        var group = harness.fixture.group
        group.pinnedRate = PinnedRate(from: "EUR", to: "USD", rate: Decimal(string: "1.1")!)
        try harness.fixture.services.groups.update(group)
        let provider = FormRatesStub()
        provider.latestTable = table("2026-11-01", eur: "0.8")
        let model = harness.newExpense(rates: service(provider))

        model.changeCurrency(to: "EUR")
        model.amountText = "100"
        await model.refreshRate()

        #expect(model.convertedTotal == usd(11_000))
        #expect(provider.log.isEmpty)
    }

    @Test func theLatestRateFillsInWhenTheDayIsUnknown() async throws {
        let harness = try ExpenseFormHarness()
        let provider = FormRatesStub()
        provider.latestTable = table("2026-11-01", eur: "0.8")
        let model = harness.newExpense(rates: service(provider))

        model.changeCurrency(to: "EUR")
        model.amountText = "100"
        await model.refreshRate()

        #expect(model.convertedTotal == usd(12_500))
    }

    @Test func offlineShowsNothingAndNeverBlocksSaving() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense(rates: service(FormRatesStub()))
        model.changeCurrency(to: "EUR")
        model.amountText = "100"
        model.title = "Hotel"
        await model.refreshRate()

        #expect(model.convertedTotal == nil)
        #expect(model.lacksRate)
        #expect(!model.isFindingRate)
        #expect(model.canSave)
        let saved = try model.save()
        #expect(saved.total.currencyCode == "EUR")
    }

    @Test func changingTheDateLooksTheRateUpAgain() async throws {
        let harness = try ExpenseFormHarness()
        let provider = FormRatesStub()
        let first = harness.fixture.clock.start
        let second = first.addingTimeInterval(-3 * 86_400)
        provider.setHistorical(table(formattedDay(first), eur: "0.5"), day: formattedDay(first))
        provider.setHistorical(table(formattedDay(second), eur: "0.25"), day: formattedDay(second))
        let model = harness.newExpense(rates: service(provider))
        model.changeCurrency(to: "EUR")
        model.amountText = "100"
        await model.refreshRate()
        #expect(model.convertedTotal == usd(20_000))
        let firstKey = model.rateKey

        model.date = second
        #expect(model.rateKey != firstKey)
        await model.refreshRate()
        #expect(model.convertedTotal == usd(40_000))
    }

    @Test func changingTheCurrencyLooksTheRateUpAgain() async throws {
        let harness = try ExpenseFormHarness()
        let provider = FormRatesStub()
        provider.latestTable = RateTable(
            base: "USD", day: "2026-11-01",
            rates: ["EUR": Decimal(string: "0.5")!, "GBP": Decimal(string: "0.25")!], fetchedAt: Date()
        )
        let model = harness.newExpense(rates: service(provider))
        model.amountText = "100"
        model.changeCurrency(to: "EUR")
        await model.refreshRate()
        #expect(model.convertedTotal == usd(20_000))

        model.changeCurrency(to: "GBP")
        await model.refreshRate()
        #expect(model.convertedTotal == usd(40_000))

        model.changeCurrency(to: "USD")
        await model.refreshRate()
        #expect(model.convertedTotal == nil)
        #expect(!model.lacksRate)
    }
}
