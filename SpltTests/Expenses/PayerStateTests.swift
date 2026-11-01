import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Payer state")
struct PayerStateTests {
    private let us = Locale(identifier: "en_US")
    private let a = PersonID(), b = PersonID()
    private let total = Money(minorUnits: 6000, currencyCode: "USD")

    @Test func singlePayerPaysEverything() {
        var state = PayerState()
        #expect(state.payers(total: total, locale: us) == .issue(.noPayer))
        state.single = a
        #expect(state.payers(total: total, locale: us) == .payers([a: total]))
    }

    @Test func severalPayersMustAddUp() {
        var state = PayerState()
        state.isMultiple = true
        state.selected = [a, b]
        state.amounts = [a: "40", b: "10"]
        let short = Money(minorUnits: 1000, currencyCode: "USD")
        #expect(state.payers(total: total, locale: us) == .issue(.payersShort(short)))
        #expect(state.remaining(total: total, locale: us) == short)

        state.amounts[b] = "30"
        let over = Money(minorUnits: 1000, currencyCode: "USD")
        #expect(state.payers(total: total, locale: us) == .issue(.payersOver(over)))
        #expect(state.remaining(total: total, locale: us)?.minorUnits == -1000)

        state.amounts[b] = "20"
        #expect(state.payers(total: total, locale: us) == .payers([
            a: Money(minorUnits: 4000, currencyCode: "USD"), b: Money(minorUnits: 2000, currencyCode: "USD")
        ]))
    }

    @Test func splitEvenlyHandsOutTheOddCent() {
        var state = PayerState()
        state.isMultiple = true
        state.selected = [a, b]
        state.splitEvenly(total: Money(minorUnits: 1001, currencyCode: "USD"), locale: us)
        let amounts = [a, b].compactMap { AmountInput.money(state.amounts[$0, default: ""], currencyCode: "USD", locale: us)?.minorUnits }
        #expect(amounts.reduce(0, +) == 1001)
        #expect(Set(amounts) == [500, 501])
    }

    @Test func existingPayersOpenInTheRightMode() {
        let one = PayerState(payers: [a: total], locale: us)
        #expect(!one.isMultiple)
        #expect(one.single == a)
        let two = PayerState(payers: [a: total, b: total], locale: us)
        #expect(two.isMultiple)
        #expect(two.selected == [a, b])
    }
}
