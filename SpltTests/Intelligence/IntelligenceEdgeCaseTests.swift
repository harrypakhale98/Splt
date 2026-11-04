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

    @Test func hyphenatedNumbersAreRead() {
        #expect(parse("twenty-five dollars lunch").amount == money(2500))
        #expect(parse("Lunch Ninety-Nine").amount == money(9900))
    }

    @Test func absurdNumbersDoNotCrash() {
        let words = "two" + String(repeating: " hundred", count: 40)
        #expect(!NumberWords.replacingSpelledNumbers(in: words).isEmpty)
        #expect(!NumberWords.replacingSpelledNumbers(in: "two" + String(repeating: " thousand", count: 40)).isEmpty)
        #expect(NumberWords.replacingSpelledNumbers(in: "two thousand five hundred") == "2500")
        #expect(NumberWords.replacingSpelledNumbers(in: "twelve hundred") == "1200")
        #expect(QuickAddValidator.writtenAmounts(in: "99999999999999999k", currencyCode: "JPY").isEmpty)
    }

    @Test func aNoteMayStartWithPaidBy() {
        let draft = parse("paid by Sam dinner 40")
        #expect(draft.payer == .person("Sam"))
        #expect(draft.amount == money(4000))
        #expect(draft.title == "Dinner")
        #expect(parse("paid by me dinner 40").payer == .me)
        #expect(parse("paid 40 for dinner").payer == .me)
    }

    @Test func titlesKeepEmojiWhole() {
        #expect(parse("\u{2708}\u{FE0F} trip 200").title == "\u{2708}\u{FE0F} trip")
        #expect(parse("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} outing 20").title == "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} outing")
        #expect(parse("Pizza \u{1F355} 20").title == "Pizza \u{1F355}")
        #expect(parse("= dinner + 20").title == "Dinner")
    }

    @Test func insightsMayNotOpenWithAnInventedName() {
        let input = InsightInput(
            groupName: "Flat", expenseCount: 3, categories: [.init(name: "Food", minorUnits: 100)],
            members: [.init(name: "Sam", paidMinorUnits: 100)]
        )
        #expect(InsightSummarizer.validated("Bob covered most of it.", for: input) == nil)
        #expect(InsightSummarizer.validated("Sam covered most of it.", for: input) != nil)
        #expect(InsightSummarizer.validated("Most of it went to food.", for: input) != nil)
        #expect(InsightSummarizer.validated("Everyone has paid a similar amount.", for: input) != nil)
        #expect(InsightSummarizer.validated("Food was the biggest part. Bob paid the rest.", for: input) == nil)
    }

    @Test func insightPercentagesSurviveHugeTotals() {
        #expect(InsightSummarizer.percent(.max / 2, of: .max) == 50)
    }

    @Test func absurdReceiptPricesAreIgnored() {
        let quantity = receipt(["CAFE", "Tea", "99 x 999999999999999.99", "TOTAL 3.00"])
        #expect(quantity.items.isEmpty)
        let many = receipt(["CAFE"] + Array(repeating: "Tea 999999999999999.99", count: 100) + ["TOTAL 3.00"])
        #expect(many.items.isEmpty)
        #expect(many.total == money(300))
    }

    @Test func aNumberAfterFlightIsThePriceWhenItIsTheOnlyOne() {
        #expect(parse("flight 300 with Sam").amount == money(30000))
        #expect(parse("flight 300 with Sam").title == "Flight")
        #expect(parse("bus 20").amount == money(2000))
        #expect(parse("room 120 for 3 nights").amount == money(12000))
        #expect(parse("dinner at table 12 for 85").amount == money(8500))
    }

    @Test func notesAndTheEngineAgreeOnEveryCurrency() {
        for code in Locale.commonISOCurrencyCodes {
            #expect(MinorUnitParser.fractionDigits(for: code) == Currency.minorUnitExponent(for: code), "\(code)")
        }
        #expect(parse("dinner 1500", code: "HUF").amount == money(150_000, "HUF"))
        #expect(parse("dinner 5000", code: "IQD").amount == money(5_000_000, "IQD"))
    }
}
