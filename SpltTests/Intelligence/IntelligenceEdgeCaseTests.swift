import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Intelligence edge cases")
@MainActor
struct IntelligenceEdgeCaseTests {
    private let rules = RuleBasedQuickAddParser()

    private func parse(_ text: String, names: [String] = ["Sam", "Priya"], code: String = "USD") -> QuickAddDraft {
        rules.parseNow(text, context: QuickAddContext(candidateNames: names, defaultCurrencyCode: code))
    }

    private func money(_ units: Int64, _ code: String = "USD") -> Money {
        Money(minorUnits: units, currencyCode: code)
    }

    private func receipt(_ rows: [String], code: String = "USD") -> ParsedReceipt {
        let lines = rows.enumerated().map { offset, text in
            ReceiptTextLine(text: text, boundingBox: CGRect(x: 0, y: 1 - CGFloat(offset) * 0.03, width: 1, height: 0.02))
        }
        let options = ReceiptParsingOptions(defaultCurrencyCode: code, locale: Locale(identifier: "en_US"), referenceDate: Date())
        return ReceiptRowParser.parse(lines: lines, options: options)
    }

    @Test func unitsAreNotThousands() {
        #expect(parse("rice 5kg 20").amount == money(2000))
        #expect(parse("taxi 12km 300").amount == money(30000))
        #expect(parse("laptop $5.5k").amount == money(550_000))
        #expect(parse("hotel 1.2K with Priya").amount == money(120_000))
    }

    @Test func centsAreReadAsCents() {
        #expect(parse("coffee 50 cents").amount == money(50))
        #expect(parse("coffee fifty cents").amount == money(50))
        #expect(parse("five cents candy").amount == money(5))
        #expect(parse("twelve dollars and fifty cents lunch").amount == money(1250))
        #expect(parse("twelve dollars and fifty cents lunch").title == "Lunch")
        #expect(parse("tea 5 dollars 5 cents").amount == money(505))
        #expect(parse("stamp 80 pence").amount == money(80, "GBP"))
        #expect(parse("chai 50 paise").amount == money(50, "INR"))
    }

    @Test func currencyWordsAwayFromAnAmountAreNotCurrency() {
        #expect(parse("pound cake 5").amount == money(500))
        #expect(parse("euro trip 300").amount == money(30000))
        #expect(parse("dollar store 200", code: "INR").amount == money(20000, "INR"))
        #expect(parse("dinner 30 in euros").amount == money(3000, "EUR"))
        #expect(parse("coffee 4.80 euros").amount == money(480, "EUR"))
        #expect(parse("dinner euro 30").amount == money(3000, "EUR"))
    }

    @Test func productNamesOnAReceiptAreNotItsCurrency() {
        #expect(receipt(["BURGER SHOP", "QUARTER POUND BURGER 5.99", "TOTAL 5.99"]).currencyCode == "USD")
        #expect(receipt(["DOLLAR STORE", "SOAP 150.00", "TOTAL 150.00"], code: "INR").currencyCode == "INR")
        #expect(receipt(["CAFE", "Tea 3.00", "TOTAL EUR 3.00"]).currencyCode == "EUR")
        #expect(receipt(["CAFE", "Tea 3.00", "TOTAL EURO 3.00"]).currencyCode == "EUR")
        #expect(receipt(["CAFE", "Chai Rs. 30.00", "TOTAL Rs. 30.00"]).currencyCode == "INR")
        #expect(receipt(["CAFE", "Tea £3.00", "TOTAL £3.00"]).currencyCode == "GBP")
    }
}
