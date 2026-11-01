import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Settle model")
struct SettleModelTests {
    private let english = Locale(identifier: "en_US")

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "splt.tests.settle.\(UUID().uuidString)")!
    }

    /// Me paid 30.00 for three people: Sam and Priya each owe 10.00.
    private func scene() throws -> (fixture: Fixture, debts: [Debt]) {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let debts = try fixture.services.groups.balances(for: fixture.group.id).suggestedSettlements
        return (fixture, debts)
    }

    private func model(_ fixture: Fixture, debts: [Debt], defaults: UserDefaults? = nil) -> SettleModel {
        SettleModel(
            route: SettleRoute(groupID: fixture.group.id, debts: debts),
            services: fixture.services, defaults: defaults ?? self.defaults(), locale: english
        )
    }

    @Test func recordsTheFullAmountOfOneDebt() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        #expect(model.amount == usdAmount(1000))
        #expect(model.canRecord)
        let receipt = try #require(model.record())
        #expect(receipt.paymentIDs.count == 1)

        let payments = try fixture.services.payments.payments(in: fixture.group.id)
        #expect(payments.first?.payer == fixture.sam.id)
        #expect(payments.first?.receiver == fixture.me.id)
        let balance = try fixture.services.people.friendBalance(with: fixture.sam.id)
        #expect(balance.isSettled)
    }

    @Test func partialPaymentLeavesTheRest() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        model.amountMode = .partial
        #expect(model.amountText == "10.00")
        model.amountText = "4.00"
        #expect(model.amount == usdAmount(400))
        #expect(model.isPartial)
        #expect(model.remaining == usdAmount(600))
        model.record()
        let balance = try fixture.services.people.friendBalance(with: fixture.sam.id)
        #expect(balance.total == [usdAmount(600)])
    }

    @Test func rejectsAnAmountThatIsNotAllowed() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        model.amountMode = .partial

        model.amountText = ""
        #expect(model.amountIssue == .empty)
        #expect(!model.canRecord)
        model.amountText = "abc"
        #expect(model.amountIssue == .invalid)
        model.amountText = "0"
        #expect(model.amountIssue == .notPositive)
        model.amountText = "25"
        #expect(model.amountIssue == .exceedsBalance(usdAmount(1000)))
        #expect(!model.canRecord)
        #expect(model.record() == nil)

        model.isReversed = true
        #expect(model.amountIssue == nil)
        #expect(model.canRecord)
    }

    @Test func reversingSwapsPayerAndReceiver() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        #expect(model.payer == fixture.sam.id)
        #expect(model.receiver == fixture.me.id)
        model.isReversed = true
        #expect(model.payer == fixture.me.id)
        #expect(model.receiver == fixture.sam.id)
        #expect(model.directionOptions.map(\.title) == ["Sam pays you", "You pay Sam"])
    }

    @Test func settlingAWholeGroupSquaresIt() throws {
        let (fixture, debts) = try scene()
        #expect(debts.count == 2)
        let model = model(fixture, debts: debts)
        #expect(model.isBatch)
        let receipt = try #require(model.record())
        #expect(receipt.paymentIDs.count == 2)
        #expect(receipt.total == [usdAmount(2000)])
        #expect(try fixture.services.groups.balances(for: fixture.group.id).isSettled)
    }

    @Test func undoReversesTheRecordedPayments() throws {
        let (fixture, debts) = try scene()
        let model = model(fixture, debts: debts)
        model.record()
        #expect(model.receipt != nil)
        model.undo()
        #expect(model.receipt == nil)
        #expect(try !fixture.services.groups.balances(for: fixture.group.id).isSettled)
        #expect(model.canRecord)
    }

    @Test func recordsOnlyOnce() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first)
        let model = model(fixture, debts: [debt])
        model.record()
        #expect(!model.canRecord)
        #expect(model.record() == nil)
        #expect(try fixture.services.payments.payments(in: fixture.group.id).count == 1)
    }

    @Test func noteCarriesTheMethod() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        model.method = .venmo
        model.note = "Dinner"
        model.record()
        let payment = try #require(try fixture.services.payments.payments(in: fixture.group.id).first)
        #expect(payment.note == "Venmo: Dinner")
    }

    @Test func remembersTheLastMethod() throws {
        let (fixture, debts) = try scene()
        let store = defaults()
        let first = model(fixture, debts: debts, defaults: store)
        #expect(first.method == .cash)
        first.method = .zelle
        let second = model(fixture, debts: debts, defaults: store)
        #expect(second.method == .zelle)
    }

    @Test func payWithOnlyWhenYouPay() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        model.method = .venmo
        #expect(model.payWithURL == nil)
        model.isReversed = true
        #expect(model.payWithURL?.scheme == "venmo")
        model.method = .cash
        #expect(model.payWithURL == nil)
    }

    @Test func describesTheTransfers() throws {
        let (fixture, debts) = try scene()
        let model = model(fixture, debts: debts)
        #expect(model.sentence(payer: fixture.sam.id, receiver: fixture.me.id) == "Sam pays you")
        #expect(model.sentence(payer: fixture.me.id, receiver: fixture.priya.id) == "You pay Priya")
        #expect(model.sentence(payer: fixture.sam.id, receiver: fixture.priya.id) == "Sam pays Priya")
    }
}
