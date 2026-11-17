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

    @Test func mineKeepsThePaymentAndLearnsFromIt() throws {
        let file = PaymentInboxFile(url: FileManager.default.temporaryDirectory.appending(path: "Mine-\(UUID().uuidString).json"))
        defer { try? FileManager.default.removeItem(at: file.url) }
        let caught = try #require(file.update {
            $0.capture(merchant: "Blue Bottle", amount: Money(minorUnits: 640, currencyCode: "USD"), date: now, source: .wallet, now: now)
        })
        #expect(NotSharedIntent.markMine(caught.payment.id, in: file, now: now))
        let state = file.read()
        #expect(state.payment(id: caught.payment.id)?.status == .dismissed)
        #expect(state.pending.isEmpty)
        #expect(state.memory(for: caught.payment)?.dismissCount == 1)
        // a second tap, or one after the app already split it, changes nothing
        #expect(!NotSharedIntent.markMine(caught.payment.id, in: file, now: now))
        #expect(file.read().memory(for: caught.payment)?.dismissCount == 1)
    }

    @Test func mineOnAPaymentThatIsGoneDoesNothing() {
        let file = PaymentInboxFile(url: FileManager.default.temporaryDirectory.appending(path: "Mine-\(UUID().uuidString).json"))
        defer { try? FileManager.default.removeItem(at: file.url) }
        #expect(!NotSharedIntent.markMine(UUID(), in: file, now: now))
    }

    @Test func toSplitKeepsEachPaymentsGroupAndReadsOlderSaves() throws {
        let id = UUID()
        let snapshot = ToSplitSnapshot(counted: [id], targets: [id: "Lisbon"])
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(ToSplitSnapshot.self, from: data).targets[id] == "Lisbon")
        let older = Data(#"{"reviewed":[],"counted":[]}"#.utf8)
        #expect(try JSONDecoder().decode(ToSplitSnapshot.self, from: older).targets.isEmpty)
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
