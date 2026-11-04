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

    /// Grouping follows the locale: lakh and crore in India, not every three digits.
    @Test func displayUsesTheLocalesGrouping() {
        let india = Locale(identifier: "en_IN")
        #expect(AmountKeypad.display("100000", locale: india) == "1,00,000")
        #expect(AmountKeypad.display("12345678.5", locale: india) == "1,23,45,678.5")
        #expect(AmountKeypad.display("-100000", locale: india) == "-1,00,000")
        #expect(AmountKeypad.display("1234567", locale: german) == "1.234.567")
    }

    /// The numerals match the amounts on every other screen, and read back as the same money.
    @Test func displayUsesTheLocalesDigits() {
        let arabic = Locale(identifier: "ar_SA")
        #expect(AmountKeypad.digit(3, locale: arabic) == "\u{0663}")
        #expect(AmountKeypad.digit(3, locale: us) == "3")
        let separator = AmountKeypad.decimalSeparator(arabic)
        #expect(AmountKeypad.display("12\(separator)5", locale: arabic) == "\u{0661}\u{0662}\(separator)\u{0665}")
        let typed = "12\(separator)5"
        #expect(AmountInput.money(typed, currencyCode: "USD", locale: arabic)?.minorUnits == 1250)
    }

    @Test func displayKeepsTextItCannotRead() {
        #expect(AmountKeypad.display("12a", locale: us) == "12a")
        #expect(AmountKeypad.display(".5", locale: us) == ".5")
    }

    @Test func symbolFollowsTheNumberWhereTheLocaleSaysSo() {
        #expect(AmountKeypad.symbolLeads(currencyCode: "USD", locale: us))
        #expect(!AmountKeypad.symbolLeads(currencyCode: "EUR", locale: german))
        #expect(AmountKeypad.symbolLeads(currencyCode: "INR", locale: Locale(identifier: "en_IN")))
    }

    @Test func typedTextParsesBackAsMoney() {
        let text = type([.digit(1), .digit(2), .decimal, .digit(5)])
        #expect(AmountInput.money(text, currencyCode: "USD", locale: us)?.minorUnits == 1250)
    }
}
