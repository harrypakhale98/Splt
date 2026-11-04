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
}
