import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Payment repository")
struct PaymentRepositoryTests {
    private func owingSam() throws -> Fixture {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        return fixture
    }

    @Test func recordingAPaymentSettlesTheBalance() throws {
        let fixture = try owingSam()
        let payment = Payment(
            groupID: fixture.group.id, payer: fixture.sam.id, receiver: fixture.me.id,
            amount: usdAmount(1500), date: fixture.clock.start
        )
        try fixture.services.payments.record(payment)
        #expect(try fixture.services.payments.payment(id: payment.id) == payment)
        #expect(try fixture.services.groups.balances(for: fixture.group.id).isSettled)
        let latest = try #require(try fixture.services.activity.entries(in: fixture.group.id, limit: 1).first)
        #expect(latest.event.kind == .paymentRecorded)
        #expect(latest.actorID == fixture.me.id)
    }

    @Test func settlingASuggestedDebtMakesTheMatchingPayment() throws {
        let fixture = try owingSam()
        let debt = try #require(try fixture.services.groups.balances(for: fixture.group.id).suggestedSettlements.first)
        let payment = try fixture.services.payments.settle(debt, in: fixture.group.id, date: fixture.clock.start)
        #expect(payment.payer == fixture.sam.id)
        #expect(payment.receiver == fixture.me.id)
        #expect(payment.amount == usdAmount(1500))
        #expect(try fixture.services.groups.balances(for: fixture.group.id).isSettled)
    }

    @Test func rejectsInvalidPayments() throws {
        let fixture = try Fixture()
        let same = Payment(groupID: fixture.group.id, payer: fixture.me.id, receiver: fixture.me.id, amount: usdAmount(100), date: fixture.clock.start)
        #expect(throws: DataError.invalidPayment(.samePerson)) { try fixture.services.payments.record(same) }
        let zero = Payment(groupID: fixture.group.id, payer: fixture.me.id, receiver: fixture.sam.id, amount: usdAmount(0), date: fixture.clock.start)
        #expect(throws: DataError.invalidPayment(.nonPositiveAmount)) { try fixture.services.payments.record(zero) }
        let loose = Payment(payer: fixture.me.id, receiver: fixture.sam.id, amount: usdAmount(100), date: fixture.clock.start)
        #expect(throws: DataError.missingGroup) { try fixture.services.payments.record(loose) }
    }

    @Test func undoingASettlementRestoresTheDebtAndIsLogged() throws {
        let fixture = try owingSam()
        let debt = try #require(try fixture.services.groups.balances(for: fixture.group.id).suggestedSettlements.first)
        let payment = try fixture.services.payments.settle(debt, in: fixture.group.id, date: fixture.clock.start)
        try fixture.services.payments.undo(id: payment.id)
        #expect(try fixture.services.groups.balances(for: fixture.group.id).net(for: fixture.sam.id) == [usdAmount(-1500)])
        #expect(try fixture.services.payments.payments(in: fixture.group.id).isEmpty)
        #expect(try fixture.services.payments.payments(in: fixture.group.id, includeDeleted: true).count == 1)
        let latest = try #require(try fixture.services.activity.entries(in: fixture.group.id, limit: 1).first)
        #expect(latest.event.kind == .paymentUndone)
    }

    @Test func undoingTwiceLogsOnceAndRestoreBringsItBack() throws {
        let fixture = try owingSam()
        let debt = try #require(try fixture.services.groups.balances(for: fixture.group.id).suggestedSettlements.first)
        let payment = try fixture.services.payments.settle(debt, in: fixture.group.id, date: fixture.clock.start)
        try fixture.services.payments.undo(id: payment.id)
        try fixture.services.payments.undo(id: payment.id)
        let undone = try fixture.services.activity.entries(in: fixture.group.id, limit: 50).filter { $0.event.kind == .paymentUndone }
        #expect(undone.count == 1)
        try fixture.services.payments.restore(id: payment.id)
        #expect(try fixture.services.groups.balances(for: fixture.group.id).isSettled)
    }

    @Test func undoingAnUnknownPaymentThrows() throws {
        let fixture = try Fixture()
        #expect(throws: DataError.self) { try fixture.services.payments.undo(id: PaymentID()) }
    }
}
