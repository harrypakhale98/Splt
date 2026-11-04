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
        #expect(model.remaining == usdAmount(600))
        model.record()
        let balance = try fixture.services.people.friendBalance(with: fixture.sam.id)
        #expect(balance.total == [usdAmount(600)])
    }

    @Test func whatRemainsIsStillKnownAfterRecording() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        model.setFraction(0.4)
        model.record()
        #expect(model.receipt != nil)
        #expect(model.remaining == usdAmount(600))
        #expect(model.amount == usdAmount(400))
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
        #expect(model.headline == "You pay Sam")
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

    @Test func theShareFollowsTheAmount() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        #expect(model.fraction == 1)
        #expect(model.step == 100)
        model.setFraction(0.5)
        #expect(model.amountMode == .partial)
        #expect(model.amount == usdAmount(500))
        #expect(model.fraction == 0.5)
        model.setFraction(0.333)
        #expect(model.amount == usdAmount(300))
        model.setFraction(0.99)
        #expect(model.amountMode == .full)
        #expect(model.amount == usdAmount(1000))
    }

    @Test func theShareNeverDropsBelowOneStep() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        model.setFraction(0)
        #expect(model.amount == usdAmount(100))
        model.setFraction(-3)
        #expect(model.amount == usdAmount(100))
    }

    @Test func theStepperMovesByWholeUnits() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        model.nudge(by: -1)
        #expect(model.amount == usdAmount(900))
        #expect(model.amountMode == .partial)
        model.nudge(by: -3)
        #expect(model.amount == usdAmount(600))
        model.nudge(by: 10)
        #expect(model.amountMode == .full)
        #expect(model.amount == usdAmount(1000))
        model.nudge(by: -20)
        #expect(model.amount == usdAmount(100))
    }

    @Test func smallDebtsStepByTenthsAndAdvancesMayGoHigher() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Gum", cents: 300)
        let debt = try #require(try fixture.services.groups.balances(for: fixture.group.id).suggestedSettlements.first)
        let model = model(fixture, debts: [debt])
        #expect(model.step == 10)
        model.isReversed = true
        model.nudge(by: 100)
        #expect(model.amount == usdAmount(1100))
        #expect(model.amountMode == .partial)
        model.setFraction(0.5)
        #expect(model.amount == usdAmount(1100))
    }

    @Test func partialWorksAfterSwappingWhoPays() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        model.isReversed = true
        model.setFraction(0.5)
        #expect(model.amountMode == .partial)
        #expect(model.amount == debt.amount)
        model.amountText = "2"
        #expect(model.amount == usdAmount(200))
        #expect(model.canRecord)
    }

    @Test func aSecondUndoChangesNothing() throws {
        let (fixture, debts) = try scene()
        let model = model(fixture, debts: debts)
        let receipt = try #require(model.record())
        let center = SettleUndoCenter(visibleFor: .seconds(60))
        center.show(receipt)
        #expect(center.undo(using: fixture.services.payments))
        let logged = try fixture.services.activity.entries(in: fixture.group.id, limit: 100).count
        #expect(!center.undo(using: fixture.services.payments))
        model.undo()
        model.undo()
        #expect(try fixture.services.activity.entries(in: fixture.group.id, limit: 100).count == logged)
        #expect(try fixture.services.payments.payments(in: fixture.group.id).isEmpty)
    }

    @Test func steppingUpFromTheLargestDebtDoesNotCrash() throws {
        let fixture = try Fixture()
        let debt = Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usdAmount(.max))
        let model = model(fixture, debts: [debt])
        model.nudge(by: 1)
        #expect(model.amount == debt.amount)
        #expect(model.amountMode == .full)
    }

    @Test func aDebtSmallerThanTheStepCanStillBePaidInPart() throws {
        let fixture = try Fixture()
        let debt = Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usdAmount(5))
        let model = model(fixture, debts: [debt])
        #expect(model.step == 1)
        model.setFraction(0.5)
        #expect(model.amountIssue == nil)
        #expect(model.amount == usdAmount(3))
    }

    @Test func participantsCarryDistinctColorsInPayerFirstOrder() throws {
        let (fixture, debts) = try scene()
        let debt = try #require(debts.first { $0.debtor == fixture.sam.id })
        let model = model(fixture, debts: [debt])
        #expect(model.participants.map(\.id) == [fixture.sam.id, fixture.me.id])
        model.isReversed = true
        #expect(model.participants.map(\.id) == [fixture.me.id, fixture.sam.id])
        let batch = SettleModel(
            route: SettleRoute(groupID: fixture.group.id, debts: debts), services: fixture.services,
            defaults: defaults(), locale: english
        )
        #expect(Set(batch.participants.map(\.id)) == fixture.everyone)
    }
}
