import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Spending chart")
struct SpendingChartTests {
    private let alice = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000C1")!)
    private let bob = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000C2")!)
    private var names: [PersonID: String] { [alice: "Alice", bob: "Bob"] }

    private func expense(_ cents: Int64, payer: PersonID, category: ExpenseCategory) -> Expense {
        Expense(
            title: "Item", total: usdAmount(cents), date: Date(timeIntervalSince1970: 0),
            category: category, payers: [payer: usdAmount(cents)], split: .equal(participants: [alice, bob])
        )
    }

    /// Alice pays a 100 dollar hotel and Bob logs a 30 dollar refund.
    private func hotelWithRefund() throws -> GroupTotals {
        try #require(GroupTotals.make(expenses: [
            expense(10_000, payer: alice, category: .lodging),
            expense(-3_000, payer: bob, category: .entertainment)
        ], names: names).first)
    }

    @Test func refundsStayOnTheChartSoTheRowsAddUpToTheTotal() throws {
        let totals = try hotelWithRefund()
        #expect(totals.total == usdAmount(7_000))
        #expect(totals.personRows.map(\.label) == ["Alice", "Bob"])
        #expect(totals.personRows.map(\.money.minorUnits).reduce(0, +) == totals.total.minorUnits)
        #expect(totals.categoryRows.map(\.money.minorUnits).reduce(0, +) == totals.total.minorUnits)
        #expect(totals.personRows.last?.money == usdAmount(-3_000))
    }

    @Test func rowsThatCancelOutAreLeftOff() throws {
        let totals = try #require(GroupTotals.make(expenses: [
            expense(5_000, payer: alice, category: .dining),
            expense(2_000, payer: bob, category: .dining),
            expense(-2_000, payer: bob, category: .transport),
            expense(2_000, payer: alice, category: .transport)
        ], names: names).first)
        #expect(totals.personRows.map(\.label) == ["Alice"])
        #expect(totals.categoryRows.map(\.label) == [ExpenseCategory.dining.title])
        #expect(totals.personRows.map(\.money.minorUnits).reduce(0, +) == totals.total.minorUnits)
    }

    @Test func refundBarsRunLeftFromZeroToScale() {
        let scale = SpendingScale(values: [10_000, -3_000])
        #expect(scale.hasNegatives)
        #expect(abs(scale.zero - 3.0 / 13.0) < 1e-9)
        let spend = scale.bar(for: 10_000)
        let refund = scale.bar(for: -3_000)
        #expect(abs(spend.start - scale.zero) < 1e-9)
        #expect(abs(refund.start) < 1e-9)
        #expect(abs(refund.start + refund.length - scale.zero) < 1e-9)
        #expect(abs(spend.length / refund.length - 10.0 / 3.0) < 1e-9)
        #expect(spend.start + spend.length <= 1 + 1e-9)
    }

    @Test func withoutRefundsZeroIsTheLeftEdgeAndTheLargestFillsTheWidth() {
        let scale = SpendingScale(values: [4_000, 1_000])
        #expect(!scale.hasNegatives)
        #expect(scale.zero == 0)
        #expect(abs(scale.bar(for: 4_000).length - 1) < 1e-9)
        #expect(abs(scale.bar(for: 1_000).length - 0.25) < 1e-9)
    }

    @Test func aRefundIsPrintedWithAMinusAndSpokenAsARefund() throws {
        let totals = try hotelWithRefund()
        let refund = try #require(totals.personRows.last)
        let english = Locale(identifier: "en_US")
        #expect(refund.amountText(locale: english) == "-$30.00")
        #expect(totals.personRows.first?.amountText(locale: english) == "$100.00")
        let spoken = SpendingRow.spokenSummary(totals.personRows, locale: english)
        #expect(spoken.contains("Bob, refund $30.00"))
    }

    @Test func repeatedNamesGetDistinctChartLabels() {
        let rows = ["Sam", "Sam", "Ana"].enumerated().map {
            SpendingRow(id: "\($0.offset)", label: $0.element, money: usdAmount(100), personID: nil)
        }
        #expect(SpendingRow.distinctLabels(rows) == ["Sam", "Sam (2)", "Ana"])
    }
}

@Suite("Currency order")
struct CurrencyOrderTests {
    private let ana = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000D1")!)

    private func expense(_ minor: Int64, _ currency: String) -> Expense {
        let money = Money(minorUnits: minor, currencyCode: currency)
        return Expense(
            title: "Item", total: money, date: Date(timeIntervalSince1970: 0),
            payers: [ana: money], split: .equal(participants: [ana])
        )
    }

    @Test func bigNumbersInACheapCurrencyDoNotOutrankTheGroupsOwn() {
        let expenses = [expense(1_000_000, "IDR"), expense(1_000_000, "IDR"), expense(10_000, "USD")]
        let led = GroupTotals.make(expenses: expenses, names: [:], leadCurrency: "USD")
        #expect(led.map(\.currencyCode) == ["USD", "IDR"])
    }

    @Test func withoutALeadTheMostUsedCurrencyComesFirstThenByCode() {
        let expenses = [expense(100, "USD"), expense(500_000, "JPY"), expense(200, "USD"), expense(300, "EUR")]
        let totals = GroupTotals.make(expenses: expenses, names: [:])
        #expect(totals.map(\.currencyCode) == ["USD", "EUR", "JPY"])
    }

    @Test func aLeadWithoutSpendingIsSimplyAbsent() {
        let totals = GroupTotals.make(expenses: [expense(100, "EUR")], names: [:], leadCurrency: "USD")
        #expect(totals.map(\.currencyCode) == ["EUR"])
    }
}
