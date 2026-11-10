import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Settle method")
struct SettleMethodTests {
    private let twelveFifty = Money(minorUnits: 1250, currencyCode: "USD")

    @Test func cashBankAndOtherHaveNoLink() {
        for method in [SettleMethod.cash, .bankTransfer, .other] {
            #expect(method.paymentURL(amount: twelveFifty, note: "", recipient: nil) == nil)
            #expect(!method.supportsPayWith)
        }
    }

    @Test func everyOtherMethodOffersPayWith() {
        for method in SettleMethod.allCases where method.supportsPayWith && method != .upi {
            #expect(method.paymentURL(amount: twelveFifty, note: "Dinner", recipient: nil) != nil)
        }
    }

    @Test func venmoCarriesAmountAndNote() throws {
        let url = try #require(SettleMethod.venmo.paymentURL(amount: twelveFifty, note: "Dinner & drinks", recipient: "@sam-r"))
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        #expect(url.scheme == "venmo")
        #expect(url.host == "paycharge")
        #expect(items["amount"] == "12.50")
        #expect(items["note"] == "Dinner & drinks")
        #expect(items["recipients"] == "sam-r")
        #expect(items["txn"] == "pay")
    }

    @Test func paypalAndCashAppUseHandlesOnlyWhenTheyFit() {
        #expect(SettleMethod.paypal.paymentURL(amount: twelveFifty, note: "", recipient: "samr")?.absoluteString
            == "https://paypal.me/samr/12.50USD")
        #expect(SettleMethod.paypal.paymentURL(amount: twelveFifty, note: "", recipient: "sam@example.com")?.host == "www.paypal.com")
        #expect(SettleMethod.cashApp.paymentURL(amount: twelveFifty, note: "", recipient: "$samr")?.absoluteString
            == "https://cash.app/$samr/12.50")
        #expect(SettleMethod.cashApp.paymentURL(amount: twelveFifty, note: "", recipient: "samr")?.absoluteString == "https://cash.app")
    }

    @Test func upiNeedsRupeesAndTakesAnAddress() throws {
        #expect(SettleMethod.upi.paymentURL(amount: twelveFifty, note: "", recipient: nil) == nil)
        let rupees = Money(minorUnits: 25_000, currencyCode: "INR")
        let url = try #require(SettleMethod.upi.paymentURL(amount: rupees, note: "Lunch", recipient: "sam@okaxis"))
        let text = url.absoluteString
        #expect(text.hasPrefix("upi://pay?"))
        #expect(text.contains("pa=sam@okaxis"))
        #expect(text.contains("am=250.00"))
        #expect(text.contains("cu=INR"))
        let emailLike = try #require(SettleMethod.upi.paymentURL(amount: rupees, note: "", recipient: "sam@example.com"))
        #expect(!emailLike.absoluteString.contains("pa="))
    }

    @Test func appleCashOpensMessages() {
        #expect(SettleMethod.appleCash.paymentURL(amount: twelveFifty, note: "", recipient: "+1 (555) 010-0100")?.absoluteString
            == "sms:+15550100100")
        #expect(SettleMethod.appleCash.paymentURL(amount: twelveFifty, note: "", recipient: "sam@example.com")?.absoluteString == "sms:")
    }

    @Test func notesStartWithTheMethod() {
        #expect(SettleNote.compose(method: .cash, text: "") == "Cash")
        #expect(SettleNote.compose(method: .wise, text: "  Rent  ") == "Wise: Rent")
        #expect(SettleNote.compose(method: .other, text: "Handed over") == "Handed over")
        #expect(SettleNote.compose(method: .other, text: "") == "")
    }

    @Test func dollarOnlyAppsAreNotHandedOtherCurrencies() throws {
        let euros = Money(minorUnits: 1250, currencyCode: "EUR")
        let venmo = try #require(SettleMethod.venmo.paymentURL(amount: euros, note: "", recipient: "@sam-r"))
        #expect(!venmo.absoluteString.contains("amount"))
        #expect(SettleMethod.cashApp.paymentURL(amount: euros, note: "", recipient: "$samr")?.absoluteString == "https://cash.app/$samr")
    }
}
