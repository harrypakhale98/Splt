import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Widget intents")
struct WidgetIntentTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func payment(daysAgo: Double) -> PendingPayment {
        PendingPayment(
            id: UUID(), merchant: "Nobu", amount: Money(minorUnits: 4_200, currencyCode: "USD"),
            date: now.addingTimeInterval(-daysAgo * day), source: .wallet
        )
    }

    @Test func splitLastPaymentOpensTheOneTheListShowsFirst() {
        let quiet = payment(daysAgo: 0)
        let asked = payment(daysAgo: 1)
        // the app decided not to ask about the newest one, so the list starts with the next
        let snapshot = ToSplitSnapshot(reviewed: [quiet.id, asked.id], counted: [asked.id])
        let url = SplitLastPaymentIntent.destination(pending: [quiet, asked], snapshot: snapshot, now: now)
        #expect(url == SpltWidgetKind.paymentURL(asked.id))
    }

    @Test func splitLastPaymentSkipsPaymentsAWeekOld() {
        let old = payment(daysAgo: 8)
        let url = SplitLastPaymentIntent.destination(pending: [old], snapshot: ToSplitSnapshot(), now: now)
        #expect(url == SpltWidgetKind.activityURL)
    }

    @Test func splitLastPaymentOpensToSplitWhenNothingWaits() {
        #expect(SplitLastPaymentIntent.destination(pending: [], snapshot: ToSplitSnapshot(), now: now) == SpltWidgetKind.activityURL)
    }

    @Test func totalsAddUpPerCurrency() {
        let amounts = [
            Money(minorUnits: 1_000, currencyCode: "USD"), Money(minorUnits: 500, currencyCode: "EUR"),
            Money(minorUnits: 250, currencyCode: "USD"),
        ]
        let locale = Locale(identifier: "en_US")
        let expected = MoneyFormatting.magnitudeString(Money(minorUnits: 500, currencyCode: "EUR"), locale: locale)
            + " + " + MoneyFormatting.magnitudeString(Money(minorUnits: 1_250, currencyCode: "USD"), locale: locale)
        #expect(MoneyFormatting.total(amounts, locale: locale) == expected)
    }
}
