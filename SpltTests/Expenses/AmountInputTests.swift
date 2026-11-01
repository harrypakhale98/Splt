import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Amount input")
struct AmountInputTests {
    private let us = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    @Test func readsTypedMoney() {
        #expect(AmountInput.money("12.5", currencyCode: "USD", locale: us)?.minorUnits == 1250)
        #expect(AmountInput.money("12,50", currencyCode: "EUR", locale: german)?.minorUnits == 1250)
        #expect(AmountInput.money("500", currencyCode: "JPY", locale: us)?.minorUnits == 500)
    }

    @Test func blankAndInvalidTextAreNil() {
        #expect(AmountInput.money("", currencyCode: "USD", locale: us) == nil)
        #expect(AmountInput.money("   ", currencyCode: "USD", locale: us) == nil)
        #expect(AmountInput.money("twelve", currencyCode: "USD", locale: us) == nil)
    }

    @Test func negativeNeedsPermission() {
        #expect(AmountInput.money("-5", currencyCode: "USD", locale: us) == nil)
        #expect(AmountInput.money("-5", currencyCode: "USD", locale: us, allowNegative: true)?.minorUnits == -500)
    }

    @Test func percentagesAreHundredthsOfAPercent() {
        #expect(AmountInput.basisPoints("25", locale: us) == 2500)
        #expect(AmountInput.basisPoints("33.33%", locale: us) == 3333)
        #expect(AmountInput.basisPoints("", locale: us) == nil)
        #expect(AmountInput.hundredthsText(2500, locale: us) == "25")
        #expect(AmountInput.hundredthsText(3333, locale: us) == "33.33")
        #expect(AmountInput.hundredthsText(3333, locale: german) == "33,33")
    }

    @Test func moneyTextReadsBackTheSame() {
        let money = Money(minorUnits: 123_456, currencyCode: "USD")
        let text = AmountInput.text(for: money, locale: us)
        #expect(AmountInput.money(text, currencyCode: "USD", locale: us) == money)
    }
}
