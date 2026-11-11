import Foundation
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
        // The group simplifies, so Sam also pays you what Sam owes Priya, and Priya owes you that much less.
        #expect(model.balance == [usdAmount(1300)])
        #expect(model.expenses.map(\.title).sorted() == ["Dinner"])
        #expect(model.groupRows.map(\.name) == ["Flat"])
        #expect(model.owedToYou == [usdAmount(1300)])
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

    @Test func listsSharedGroupsButNotHiddenDirectOnes() throws {
        let fixture = try Fixture()
        let model = FriendDetailModel(friendID: fixture.sam.id, services: fixture.services)
        _ = model.expenseGroup()
        let archived = SplitGroup(name: "Old", currencyCode: "USD", memberIDs: [fixture.me.id, fixture.sam.id], isArchived: true)
        try fixture.services.groups.create(archived)
        let other = SplitGroup(name: "Without Sam", currencyCode: "USD", memberIDs: [fixture.me.id, fixture.priya.id])
        try fixture.services.groups.create(other)
        model.refresh()
        #expect(model.sharedGroups.map(\.name) == ["Flat"])
    }

    @Test func worksOutWhatYouLentOrOweOnAnExpense() throws {
        let fixture = try Fixture()
        let dinner = try fixture.addExpense("Dinner", cents: 3000)
        let taxi = try fixture.addExpense("Taxi", cents: 600, paidBy: fixture.priya, splitBetween: [fixture.priya.id, fixture.sam.id])
        let model = FriendDetailModel(friendID: fixture.sam.id, services: fixture.services)
        #expect(model.myNet(in: dinner) == usdAmount(2000))
        #expect(model.myNet(in: taxi) == nil)
        #expect(model.payerText(for: dinner) == "you")
        #expect(model.payerText(for: taxi) == "Priya")
    }

    @Test func groupsTheTimelineByMonthNewestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func expense(_ title: String, _ month: Int, _ day: Int) -> Expense {
            Expense(
                title: title, total: usdAmount(100),
                date: calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!,
                paidBy: PersonID(), split: .equal(participants: [PersonID()])
            )
        }
        let months = FriendTimeline.months(
            [expense("a", 3, 4), expense("b", 5, 1), expense("c", 3, 20), expense("d", 5, 28)], calendar: calendar
        )
        #expect(months.count == 2)
        #expect(months[0].expenses.map(\.title) == ["d", "b"])
        #expect(months[1].expenses.map(\.title) == ["c", "a"])
        #expect(months[0].start > months[1].start)
        #expect(FriendTimeline.months([], calendar: calendar).isEmpty)
    }
}
