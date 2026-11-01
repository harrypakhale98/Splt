import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Friend detail model")
struct FriendDetailModelTests {
    @Test func showsBalanceExpensesAndGroups() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        try fixture.addExpense("Taxi", cents: 600, paidBy: fixture.priya, splitBetween: [fixture.priya.id, fixture.sam.id])
        let model = FriendDetailModel(friendID: fixture.sam.id, services: fixture.services)
        #expect(model.friend?.name == "Sam")
        #expect(model.balance == [usdAmount(1000)])
        #expect(model.expenses.map(\.title).sorted() == ["Dinner"])
        #expect(model.groupRows.map(\.name) == ["Flat"])
        #expect(model.owedToYou == [usdAmount(1000)])
        #expect(model.settleRequest?.legs.count == 1)
        #expect(!model.isSettled)
    }

    @Test func aSettledFriendOffersNothingToSettle() throws {
        let fixture = try Fixture()
        let model = FriendDetailModel(friendID: fixture.sam.id, services: fixture.services)
        #expect(model.isSettled)
        #expect(model.settleRequest == nil)
        #expect(model.owedToYou.isEmpty)
    }

    @Test func listsPaymentsBetweenTheTwoOfYou() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let toMe = Payment(groupID: fixture.group.id, payer: fixture.sam.id, receiver: fixture.me.id, amount: usdAmount(400), date: fixture.clock.start)
        let other = Payment(groupID: fixture.group.id, payer: fixture.priya.id, receiver: fixture.me.id, amount: usdAmount(500), date: fixture.clock.start)
        try fixture.services.payments.record(toMe)
        try fixture.services.payments.record(other)
        let model = FriendDetailModel(friendID: fixture.sam.id, services: fixture.services)
        #expect(model.payments.map(\.id) == [toMe.id])
        #expect(model.balance == [usdAmount(600)])
    }

    @Test func undoAndRestoreChangeTheBalance() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let payment = Payment(groupID: fixture.group.id, payer: fixture.sam.id, receiver: fixture.me.id, amount: usdAmount(1000), date: fixture.clock.start)
        try fixture.services.payments.record(payment)
        let model = FriendDetailModel(friendID: fixture.sam.id, services: fixture.services)
        #expect(model.isSettled)

        model.undo(payment)
        #expect(model.balance == [usdAmount(1000)])
        let undone = try #require(model.payments.first)
        #expect(undone.isDeleted)

        model.restore(undone)
        #expect(model.isSettled)
    }

    @Test func renamingTrimsAndSaves() throws {
        let fixture = try Fixture()
        let model = FriendDetailModel(friendID: fixture.sam.id, services: fixture.services)
        model.rename(to: "  Samuel   Reed ")
        #expect(model.friend?.name == "Samuel Reed")
        model.rename(to: "   ")
        #expect(model.friend?.name == "Samuel Reed")
    }

    @Test func newExpensesGoToOneHiddenDirectGroup() throws {
        let fixture = try Fixture()
        let model = FriendDetailModel(friendID: fixture.sam.id, services: fixture.services)
        let first = try #require(model.expenseGroup())
        let second = try #require(model.expenseGroup())
        #expect(first == second)
        let group = try #require(try fixture.services.groups.group(id: first))
        #expect(group.kind == .friend)
        #expect(Set(group.memberIDs) == [fixture.me.id, fixture.sam.id])
        #expect(group.name == "Sam")
    }

    @Test func directExpensesCountInTheFriendBalance() throws {
        let fixture = try Fixture()
        let model = FriendDetailModel(friendID: fixture.sam.id, services: fixture.services)
        let direct = try #require(model.expenseGroup())
        try fixture.services.expenses.add(Expense(
            groupID: direct, title: "Coffee", total: usdAmount(800), date: fixture.clock.start,
            paidBy: fixture.me.id, split: .equal(participants: [fixture.me.id, fixture.sam.id])
        ))
        model.refresh()
        #expect(model.balance == [usdAmount(400)])
        #expect(model.groupRows.first?.name == "Direct expenses")
        #expect(model.expenses.map(\.title) == ["Coffee"])
    }

    @Test func anUnknownFriendLoadsAsMissing() throws {
        let fixture = try Fixture()
        let model = FriendDetailModel(friendID: PersonID(), services: fixture.services)
        #expect(model.friend == nil)
        #expect(model.didLoad)
    }
}
