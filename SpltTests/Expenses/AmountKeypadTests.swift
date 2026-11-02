import Foundation
import Testing
@testable import Splt

@Suite("Amount keypad")
struct AmountKeypadTests {
    private let us = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    private func type(_ keys: [AmountKey], exponent: Int = 2, locale: Locale? = nil) -> String {
        keys.reduce("") { AmountKeypad.apply($1, to: $0, exponent: exponent, locale: locale ?? us) }
    }

    @Test func digitsBuildTheAmount() {
        #expect(type([.digit(4), .digit(2)]) == "42")
    }

    @Test func leadingZerosAreReplaced() {
        #expect(type([.digit(0), .digit(7)]) == "7")
        #expect(type([.digit(0), .digit(0)]) == "0")
    }

    @Test func decimalSeparatorFollowsTheLocale() {
        #expect(type([.digit(1), .decimal, .digit(5)]) == "1.5")
        #expect(type([.digit(1), .decimal, .digit(5)], locale: german) == "1,5")
        #expect(type([.decimal, .digit(5)]) == "0.5")
    }

    @Test func onlyOneSeparatorAndLimitedFractionDigits() {
        #expect(type([.digit(1), .decimal, .decimal, .digit(2)]) == "1.2")
        #expect(type([.digit(1), .decimal, .digit(2), .digit(3), .digit(4)]) == "1.23")
    }

    @Test func zeroDecimalCurrenciesIgnoreTheSeparator() {
        #expect(type([.digit(5), .decimal, .digit(0)], exponent: 0) == "50")
    }

    @Test func threeDecimalCurrenciesAllowThree() {
        #expect(type([.digit(1), .decimal, .digit(2), .digit(3), .digit(4), .digit(5)], exponent: 3) == "1.234")
    }

    @Test func deleteRemovesTheLastKey() {
        #expect(type([.digit(1), .digit(2), .delete]) == "1")
        #expect(type([.delete]) == "")
        #expect(type([.digit(1), .decimal, .delete]) == "1")
    }

    @Test func tooManyDigitsAreIgnored() {
        let many = Array(repeating: AmountKey.digit(9), count: 12)
        #expect(type(many).count == AmountKeypad.maximumIntegerDigits)
    }

    @Test func displayGroupsThousands() {
        #expect(AmountKeypad.display("1234567.5", locale: us) == "1,234,567.5")
        #expect(AmountKeypad.display("1234,5", locale: german) == "1.234,5")
        #expect(AmountKeypad.display("", locale: us) == "")
        #expect(AmountKeypad.display("0.", locale: us) == "0.")
    }

    @Test func typedTextParsesBackAsMoney() {
        let text = type([.digit(1), .digit(2), .decimal, .digit(5)])
        #expect(AmountInput.money(text, currencyCode: "USD", locale: us)?.minorUnits == 1250)
    }
}
