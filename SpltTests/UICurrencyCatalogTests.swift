import Foundation
import Testing
@testable import Splt

@Suite("Currency catalog")
struct UICurrencyCatalogTests {
    private let english = Locale(identifier: "en_US")

    @Test func listsCommonCurrenciesWithNames() {
        let options = CurrencyCatalog.options(locale: english)
        let usd = options.first { $0.code == "USD" }
        #expect(usd?.name == "US Dollar")
        #expect(options.contains { $0.code == "EUR" })
        #expect(options.contains { $0.code == "JPY" })
    }

    @Test func namesFollowTheLocale() {
        #expect(CurrencyCatalog.name(for: "EUR", locale: Locale(identifier: "fr_FR")) == "euro")
    }

    @Test func unknownCodeFallsBackToCode() {
        #expect(CurrencyCatalog.name(for: "ZZZ", locale: english) == "ZZZ")
    }

    @Test func optionsAreSortedByName() {
        let names = CurrencyCatalog.options(locale: english).map(\.name)
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        #expect(names == sorted)
    }

    @Test func filterMatchesCodeAndNameIgnoringCase() {
        let options = CurrencyCatalog.options(locale: english)
        #expect(CurrencyCatalog.filter(options, query: "usd").contains { $0.code == "USD" })
        #expect(CurrencyCatalog.filter(options, query: "swiss").contains { $0.code == "CHF" })
        #expect(CurrencyCatalog.filter(options, query: "  ").count == options.count)
        #expect(CurrencyCatalog.filter(options, query: "qqqqqq").isEmpty)
    }
}
