import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Payment inbox")
struct PaymentInboxStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func usd(_ dollars: Int64) -> Money { Money(minorUnits: dollars * 100, currencyCode: "USD") }

    @Test func sameTapTwiceIsKeptOnce() {
        var state = PaymentInboxState()
        let first = state.capture(merchant: "NOBU #12", amount: usd(142), date: now, source: .wallet, now: now)
        let again = state.capture(merchant: "Nobu", amount: usd(142), date: now.addingTimeInterval(60), source: .wallet, now: now)
        #expect(first.isNew)
        #expect(!again.isNew)
        #expect(again.payment.id == first.payment.id)
        #expect(state.pending.count == 1)
        #expect(state.lastWalletCaptureAt == now)
    }

    @Test func samePaymentLaterIsANewOne() {
        var state = PaymentInboxState()
        state.capture(merchant: "Nobu", amount: usd(142), date: now, source: .wallet, now: now)
        let later = state.capture(merchant: "Nobu", amount: usd(142), date: now.addingTimeInterval(600), source: .wallet, now: now)
        #expect(later.isNew)
        #expect(state.pending.count == 2)
    }

    @Test func emptyMerchantGetsAName() {
        var state = PaymentInboxState()
        let caught = state.capture(merchant: "  ", amount: usd(5), date: now, source: .text, now: now)
        #expect(!caught.payment.merchant.isEmpty)
        #expect(state.lastWalletCaptureAt == nil)
    }

    @Test func merchantKeyDropsStoreNumbers() {
        #expect(MerchantKey.make("STARBUCKS #1234") == "starbucks")
        #expect(MerchantKey.make("Blue Bottle Coffee") == "blue bottle coffee")
    }

    @Test func twoDismissalsMuteAndASplitRemembers() {
        var state = PaymentInboxState()
        let one = state.capture(merchant: "Blue Bottle", amount: usd(6), date: now, source: .wallet, now: now).payment
        let two = state.capture(merchant: "Blue Bottle", amount: usd(7), date: now.addingTimeInterval(86_400), source: .wallet, now: now).payment
        let mutedAfterOne = state.resolve(id: one.id, as: .dismissed, now: now)
        let mutedAfterTwo = state.resolve(id: two.id, as: .dismissed, now: now)
        #expect(!mutedAfterOne)
        #expect(mutedAfterTwo)
        #expect(state.memory(for: one)?.isMuted == true)

        let group = UUID()
        let dinner = state.capture(merchant: "Nobu", amount: usd(90), date: now, source: .wallet, now: now).payment
        state.resolve(id: dinner.id, as: .split, groupID: group, category: .dining, now: now)
        #expect(state.memory(for: dinner)?.groupID == group)
        #expect(state.memory(for: dinner)?.category == .dining)
        #expect(state.pending.isEmpty)
    }

    @Test func wrappingUpATripDoesNotMute() {
        var state = PaymentInboxState()
        for day in 0..<3 {
            let payment = state.capture(
                merchant: "Pastelaria", amount: usd(4), date: now.addingTimeInterval(Double(day) * 86_400), source: .wallet, now: now
            ).payment
            state.resolve(id: payment.id, as: .dismissed, learns: false, now: now)
        }
        #expect(state.merchants["pastelaria"]?.isMuted != true)
    }

    @Test func oldDecisionsAreForgotten() {
        var state = PaymentInboxState()
        let payment = state.capture(merchant: "Uber", amount: usd(20), date: now, source: .wallet, now: now).payment
        state.resolve(id: payment.id, as: .split, now: now)
        state.prune(now: now.addingTimeInterval(31 * 86_400))
        #expect(state.payments.isEmpty)
    }

    @Test func monthlyChargeIsRecurring() {
        var state = PaymentInboxState()
        let first = state.capture(merchant: "Netflix", amount: usd(15), date: now, source: .wallet, now: now).payment
        #expect(!state.isRecurring(first))
        let second = state.capture(merchant: "Netflix", amount: usd(15), date: now.addingTimeInterval(30 * 86_400), source: .wallet, now: now).payment
        #expect(state.isRecurring(second))
    }
}

@Suite("Payment scoring")
struct PaymentScorerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 3, day: 10, hour: hour))!
    }

    private func payment(_ merchant: String, cents: Int64, hour: Int, currency: String = "USD") -> PendingPayment {
        PendingPayment(id: UUID(), merchant: merchant, amount: Money(minorUnits: cents, currencyCode: currency), date: at(hour: hour), source: .wallet)
    }

    @Test func bigPaymentGetsANudge() {
        let scorer = PaymentScorer(calendar: calendar)
        #expect(scorer.priority(of: payment("Apple Store", cents: 12_900, hour: 11), in: PaymentInboxState()) == .high)
    }

    @Test func morningCoffeeWaitsQuietly() {
        let scorer = PaymentScorer(calendar: calendar)
        #expect(scorer.priority(of: payment("Blue Bottle Coffee", cents: 650, hour: 8), in: PaymentInboxState()) == .normal)
    }

    @Test func dinnerIsLikelyShared() {
        let scorer = PaymentScorer(calendar: calendar)
        #expect(scorer.priority(of: payment("Pizza Restaurant", cents: 2_500, hour: 20), in: PaymentInboxState()) == .high)
        #expect(scorer.priority(of: payment("Pizza Restaurant", cents: 2_500, hour: 12), in: PaymentInboxState()) == .normal)
    }

    @Test func mutedMerchantStaysQuiet() {
        var state = PaymentInboxState()
        state.setMuted(true, merchantKey: "apple store")
        let scorer = PaymentScorer(calendar: calendar)
        #expect(scorer.priority(of: payment("Apple Store", cents: 50_000, hour: 11), in: state) == .quiet)
    }

    @Test func anythingOnATripIsShared() {
        let range = at(hour: 0)..<at(hour: 23)
        let scorer = PaymentScorer(calendar: calendar, tripRange: range)
        #expect(scorer.priority(of: payment("Kiosk", cents: 300, hour: 9, currency: "EUR"), in: PaymentInboxState()) == .high)
    }

    @Test func unknownCurrencyUsesWhatYouUsuallySpend() {
        var state = PaymentInboxState()
        let base = at(hour: 9)
        for (index, units) in [Int64(100), 120, 90, 110, 100].enumerated() {
            state.capture(merchant: "Shop \(index)", amount: Money(minorUnits: units * 100, currencyCode: "THB"),
                          date: base.addingTimeInterval(Double(index) * 3_600), source: .wallet, now: base)
        }
        #expect(PaymentScorer.bigAmount(for: "THB", in: state) == 25_000)
    }
}

@Suite("Bank text parsing")
struct PaymentTextParserTests {
    @Test func readsAnIndianUPIDebit() throws {
        let text = "Rs.1,250.00 debited from A/c XX1234 on 12-11-26 to VPA swiggy.food@icici (UPI Ref 6312). Not you? Call 1800"
        let parsed = try #require(PaymentTextParser.parse(text, localCurrency: "INR"))
        #expect(parsed.amount == Money(minorUnits: 125_000, currencyCode: "INR"))
        #expect(parsed.merchant == "swiggy food")
    }

    @Test func readsACardAlert() throws {
        let parsed = try #require(PaymentTextParser.parse("You spent $42.50 at NOBU MALIBU on your card ending 1234.", localCurrency: "USD"))
        #expect(parsed.amount == Money(minorUnits: 4_250, currencyCode: "USD"))
        #expect(parsed.merchant == "Nobu Malibu")
    }

    @Test func readsEuroWithACommaDecimal() throws {
        let parsed = try #require(PaymentTextParser.parse("Card payment of 12,50 € at Café Lisboa was charged.", localCurrency: "EUR"))
        #expect(parsed.amount == Money(minorUnits: 1_250, currencyCode: "EUR"))
    }

    @Test func skipsCodesOffersAndMoneyComingIn() {
        #expect(PaymentTextParser.parse("123456 is your OTP for a payment of Rs 500 at Amazon. Do not share.", localCurrency: "INR") == nil)
        #expect(PaymentTextParser.parse("Rs 5,000 credited to your account from Priya.", localCurrency: "INR") == nil)
        #expect(PaymentTextParser.parse("Get 20% cashback offer! Spend Rs 999 at Myntra today.", localCurrency: "INR") == nil)
        #expect(PaymentTextParser.parse("Refund of $20.00 to your card from Uber.", localCurrency: "USD") == nil)
    }

    @Test func readsIndianGrouping() {
        #expect(PaymentTextParser.decimal("1,00,000") == 100_000)
        #expect(PaymentTextParser.decimal("1.234,50") == Decimal(string: "1234.5"))
        #expect(PaymentTextParser.decimal("1.2.3") == nil)
    }

    @Test func screenshotPrefersTheTotalLine() {
        let reading = ScreenshotPaymentReader.reading(
            from: ["9:41", "Latest Transactions", "Trattoria Roma", "Pasta €18.00", "Wine €24.00", "Total €42.00"],
            localCurrency: "EUR"
        )
        #expect(reading.merchant == "Trattoria Roma")
        #expect(reading.amount == Money(minorUnits: 4_200, currencyCode: "EUR"))
    }
}

@MainActor
@Suite("Payment splitting and trips")
struct PaymentSplitterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func splitsLikeTheGroupUsuallyDoes() throws {
        let services = try DataServices.inMemory()
        let me = try services.people.ensureMe(name: "Me")
        let leo = Person(name: "Leo")
        try services.people.add(leo)
        let group = SplitGroup(name: "Flat", currencyCode: "USD", memberIDs: [me.id, leo.id])
        try services.groups.create(group)
        let payment = PendingPayment(
            id: UUID(), merchant: "Trader Joe's", amount: Money(minorUnits: 6_000, currencyCode: "USD"), date: Date(), source: .wallet
        )
        let expense = try PaymentSplitter(services: services).split(payment, into: group, category: nil)
        #expect(expense.payers == [me.id: payment.amount])
        #expect(expense.split == .equal(participants: [me.id, leo.id]))
        #expect(try services.expenses.expenses(in: group.id).count == 1)
    }

    @Test func tripCoversWholeDays() throws {
        let start = calendar.date(from: DateComponents(year: 2027, month: 5, day: 1, hour: 15))!
        let end = calendar.date(from: DateComponents(year: 2027, month: 5, day: 4, hour: 9))!
        let trip = SplitGroup(name: "Lisbon", currencyCode: "EUR", kind: .trip, tripStart: start, tripEnd: end)
        let range = try #require(SplitTargetPicker.tripRange(of: trip, calendar: calendar))
        #expect(range.lowerBound == calendar.date(from: DateComponents(year: 2027, month: 5, day: 1)))
        #expect(range.upperBound == calendar.date(from: DateComponents(year: 2027, month: 5, day: 5)))
        let lateOnLastDay = calendar.date(from: DateComponents(year: 2027, month: 5, day: 4, hour: 23))!
        #expect(SplitTargetPicker.activeTrip(among: [trip], on: lateOnLastDay, calendar: calendar)?.id == trip.id)
        #expect(SplitTargetPicker.activeTrip(among: [trip], on: range.upperBound, calendar: calendar) == nil)
    }

    @Test func paymentLinkRoundTrips() {
        let id = UUID()
        #expect(DeepLink(url: DeepLink.payment(id).url) == .payment(id))
    }
}
