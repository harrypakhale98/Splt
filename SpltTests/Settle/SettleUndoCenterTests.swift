import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Settle undo banner")
struct SettleUndoCenterTests {
    private func recordedPayment(_ fixture: Fixture) throws -> Payment {
        try fixture.addExpense("Dinner", cents: 3000)
        let payment = Payment(groupID: fixture.group.id, payer: fixture.sam.id, receiver: fixture.me.id, amount: usdAmount(1000), date: fixture.clock.start)
        try fixture.services.payments.record(payment)
        return payment
    }

    @Test func showsTheLatestReceipt() throws {
        let fixture = try Fixture()
        let center = SettleUndoCenter()
        #expect(center.banner == nil)
        let payment = try recordedPayment(fixture)
        let receipt = SettleReceipt(paymentIDs: [payment.id], message: "Sam paid you $10.00", total: [usdAmount(1000)])
        center.show(receipt)
        #expect(center.banner == .recorded(receipt))
        #expect(center.banner?.message == "Sam paid you $10.00")
    }

    @Test func undoReversesThePaymentAndSaysSo() throws {
        let fixture = try Fixture()
        let payment = try recordedPayment(fixture)
        let center = SettleUndoCenter()
        center.show(SettleReceipt(paymentIDs: [payment.id], message: "Recorded", total: []))
        #expect(try fixture.services.people.friendBalance(with: fixture.sam.id).isSettled)

        #expect(center.undo(using: fixture.services.payments))
        #expect(try fixture.services.payments.payment(id: payment.id)?.isDeleted == true)
        #expect(try fixture.services.people.friendBalance(with: fixture.sam.id).total == [usdAmount(1000)])
        #expect(center.banner == .undone("Payment undone"))
    }

    @Test func undoDoesNothingWithoutAReceipt() throws {
        let fixture = try Fixture()
        let center = SettleUndoCenter()
        #expect(!center.undo(using: fixture.services.payments))
        center.dismiss()
        #expect(center.banner == nil)
    }

    @Test func theBannerHidesItselfAfterAWhile() async throws {
        let center = SettleUndoCenter(visibleFor: .milliseconds(30))
        center.show(SettleReceipt(paymentIDs: [], message: "Recorded", total: []))
        #expect(center.banner != nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(center.banner == nil)
    }

    @Test func aNewReceiptReplacesTheOldOne() {
        let center = SettleUndoCenter()
        let first = SettleReceipt(paymentIDs: [], message: "First", total: [])
        let second = SettleReceipt(paymentIDs: [], message: "Second", total: [])
        center.show(first)
        center.show(second)
        #expect(center.banner == .recorded(second))
    }
}
