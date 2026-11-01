import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Avatar")
struct UIAvatarTests {
    @Test func initialsUseFirstAndLastWord() {
        #expect(AvatarStyle.initials(for: "Sam Rivera") == "SR")
        #expect(AvatarStyle.initials(for: "maria del carmen gonzalez") == "MG")
        #expect(AvatarStyle.initials(for: "priya") == "P")
        #expect(AvatarStyle.initials(for: "  ") == "?")
        #expect(AvatarStyle.initials(for: "") == "?")
    }

    @Test func colorIsStableForTheSameName() {
        #expect(AvatarStyle.paletteIndex(for: "Sam Rivera") == AvatarStyle.paletteIndex(for: "Sam Rivera"))
        #expect(AvatarStyle.paletteIndex(for: "Sam Rivera") == AvatarStyle.paletteIndex(for: " sam rivera "))
    }

    @Test func paletteIndexHasAKnownValue() {
        // pins the hash so colors never change between releases
        #expect(AvatarStyle.paletteIndex(for: "a") == 4)
    }

    @Test func differentNamesSpreadAcrossThePalette() {
        let names = ["Sam", "Priya", "Alex", "Jo", "Maria", "Chen", "Ola", "Ravi", "Kim", "Lee", "Noor", "Eli"]
        let indexes = Set(names.map(AvatarStyle.paletteIndex(for:)))
        #expect(indexes.count > 3)
    }
}

@Suite("Money formatting")
struct UIMoneyFormattingTests {
    private let us = Locale(identifier: "en_US")

    @Test func formatsMinorUnits() {
        #expect(MoneyFormatting.string(Money(minorUnits: 1250, currencyCode: "USD"), locale: us) == "$12.50")
        #expect(MoneyFormatting.string(Money(minorUnits: 5, currencyCode: "USD"), locale: us) == "$0.05")
    }

    @Test func respectsCurrencyExponent() {
        #expect(MoneyFormatting.string(Money(minorUnits: 2800, currencyCode: "JPY"), locale: us) == "¥2,800")
        #expect(MoneyFormatting.string(Money(minorUnits: 1500, currencyCode: "KWD"), locale: us) == "KWD\u{00A0}1.500")
    }

    @Test func balanceSignIsPartOfTheText() {
        #expect(MoneyFormatting.string(Money(minorUnits: 1250, currencyCode: "USD"), locale: us, showsSign: true) == "+$12.50")
        #expect(MoneyFormatting.string(Money(minorUnits: -1250, currencyCode: "USD"), locale: us, showsSign: true) == "-$12.50")
        #expect(MoneyFormatting.string(Money(minorUnits: 0, currencyCode: "USD"), locale: us, showsSign: true) == "$0.00")
    }

    @Test func handlesLargeAmountsExactly() {
        let money = Money(minorUnits: 9_007_199_254_740_993, currencyCode: "USD")
        #expect(MoneyFormatting.string(money, locale: us) == "$90,071,992,547,409.93")
    }

    @Test func handlesMostNegativeValue() {
        let money = Money(minorUnits: .min, currencyCode: "USD")
        #expect(MoneyFormatting.string(money, locale: us, showsSign: true).hasPrefix("-$"))
    }
}
