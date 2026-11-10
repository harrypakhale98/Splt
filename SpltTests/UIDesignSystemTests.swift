import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Plurals")
struct PluralTextTests {
    @Test func oneReadsAsOne() {
        let name = "Sam", one = 1, none = 0, two = 2
        #expect(String(localized: "\(name) imported \(one) expenses") == "Sam imported 1 expense")
        #expect(String(localized: "\(name) imported \(one) expenses and \(none) payments") == "Sam imported 1 expense and 0 payments")
        #expect(String(localized: "\(name) imported \(two) expenses and \(one) payments") == "Sam imported 2 expenses and 1 payment")
    }
}

@Suite("Group symbols")
struct GroupSymbolNameTests {
    /// VoiceOver must never fall back to the generic word or a system name for a symbol on offer.
    @Test func everySymbolOnOfferHasItsOwnSpokenName() {
        let names = GroupSymbols.all.map(GroupSymbols.spokenName(for:))
        #expect(Set(names).count == GroupSymbols.all.count)
        #expect(!names.contains(String(localized: "Symbol")))
    }
}

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
        #expect(PersonPalette.preferredIndex(forName: "Sam Rivera") == PersonPalette.preferredIndex(forName: "Sam Rivera"))
        #expect(PersonPalette.preferredIndex(forName: "Sam Rivera") == PersonPalette.preferredIndex(forName: " sam rivera "))
    }

    @Test func paletteIndexHasAKnownValue() {
        // pins the hash so colors never change between releases
        #expect(PersonPalette.preferredIndex(forName: "a") == 4)
    }

    @Test func differentNamesSpreadAcrossThePalette() {
        let names = ["Sam", "Priya", "Alex", "Jo", "Maria", "Chen", "Ola", "Ravi", "Kim", "Lee", "Noor", "Eli"]
        let indexes = Set(names.map(PersonPalette.preferredIndex(forName:)))
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

    @Test func amountKeepsItsScaleInCurrenciesShownWithoutDecimals() {
        #expect(MoneyFormatting.string(Money(minorUnits: 150_000, currencyCode: "HUF"), locale: us) == "HUF\u{00A0}1,500")
        #expect(MoneyFormatting.string(Money(minorUnits: 1_500_000, currencyCode: "IQD"), locale: us) == "IQD\u{00A0}1,500")
        #expect(MoneyFormatting.string(Money(minorUnits: 1_550, currencyCode: "HUF"), locale: us) == "HUF\u{00A0}15.50")
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
