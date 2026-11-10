import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Group repository")
struct GroupRepositoryTests {
    @Test func createsAndReadsAGroup() throws {
        let fixture = try Fixture()
        #expect(try fixture.services.groups.group(id: fixture.group.id) == fixture.group)
        #expect(try fixture.services.groups.groups(includeArchived: true).count == 1)
    }

    @Test func archivedGroupsAreHiddenUnlessAsked() throws {
        let fixture = try Fixture()
        try fixture.services.groups.setArchived(true, id: fixture.group.id)
        #expect(try fixture.services.groups.groups(includeArchived: false).isEmpty)
        #expect(try fixture.services.groups.groups(includeArchived: true).count == 1)
        try fixture.services.groups.setArchived(false, id: fixture.group.id)
        #expect(try fixture.services.groups.groups(includeArchived: false).count == 1)
    }

    @Test func updateKeepsMembersAndLogsARename() throws {
        let fixture = try Fixture()
        var edited = fixture.group
        edited.name = "Flat 4B"
        edited.simplifiesDebts = false
        edited.memberIDs = []
        try fixture.services.groups.update(edited)
        let stored = try #require(try fixture.services.groups.group(id: fixture.group.id))
        #expect(stored.name == "Flat 4B")
        #expect(!stored.simplifiesDebts)
        #expect(stored.memberIDs == fixture.group.memberIDs)
        let kinds = try fixture.services.activity.entries(in: fixture.group.id, limit: 10).map(\.event.kind)
        #expect(kinds.contains(.groupRenamed))
    }

    @Test func addingAMemberIsLoggedAndIdempotent() throws {
        let fixture = try Fixture()
        let alex = Person(name: "Alex")
        try fixture.services.people.add(alex)
        try fixture.services.groups.addMember(alex.id, to: fixture.group.id)
        try fixture.services.groups.addMember(alex.id, to: fixture.group.id)
        let stored = try #require(try fixture.services.groups.group(id: fixture.group.id))
        #expect(stored.memberIDs.filter { $0 == alex.id }.count == 1)
        let added = try fixture.services.activity.entries(in: fixture.group.id, limit: 20)
            .filter { $0.event == .memberAdded(alex.id) }
        #expect(added.count == 1)
    }

    @Test func removingASettledMemberWorksAndIsLogged() throws {
        let fixture = try Fixture()
        try fixture.services.groups.removeMember(fixture.priya.id, from: fixture.group.id)
        let stored = try #require(try fixture.services.groups.group(id: fixture.group.id))
        #expect(!stored.memberIDs.contains(fixture.priya.id))
        let entries = try fixture.services.activity.entries(in: fixture.group.id, limit: 20)
        #expect(entries.contains { $0.event == .memberRemoved(fixture.priya.id) })
    }

    @Test func removingSomeoneWhoStillOwesIsRefused() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        #expect(throws: DataError.memberStillHasBalance(fixture.sam.id)) {
            try fixture.services.groups.removeMember(fixture.sam.id, from: fixture.group.id)
        }
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.memberIDs.contains(fixture.sam.id) == true)
    }

    /// I pay for Priya and Sam pays for me: I net to zero but still owe Sam and am owed by Priya.
    private func addCrossingDebts(_ fixture: Fixture) throws {
        try fixture.addExpense(cents: 1000, paidBy: fixture.me, splitBetween: [fixture.priya.id])
        try fixture.addExpense(cents: 1000, paidBy: fixture.sam, splitBetween: [fixture.me.id])
    }

    @Test func aNetOfZeroWithDebtsLeftIsRefusedWhenDebtsAreNotSimplified() throws {
        let fixture = try Fixture(simplifies: false)
        try addCrossingDebts(fixture)
        #expect(try fixture.services.groups.balances(for: fixture.group.id).net(for: fixture.me.id).isEmpty)
        #expect(throws: DataError.memberStillHasBalance(fixture.me.id)) {
            try fixture.services.groups.removeMember(fixture.me.id, from: fixture.group.id)
        }
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.memberIDs.contains(fixture.me.id) == true)

        try fixture.services.payments.settle(
            Debt(debtor: fixture.me.id, creditor: fixture.sam.id, amount: usdAmount(1000)),
            in: fixture.group.id, date: fixture.clock.start, note: ""
        )
        try fixture.services.payments.settle(
            Debt(debtor: fixture.priya.id, creditor: fixture.me.id, amount: usdAmount(1000)),
            in: fixture.group.id, date: fixture.clock.start, note: ""
        )
        try fixture.services.groups.removeMember(fixture.me.id, from: fixture.group.id)
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.memberIDs.contains(fixture.me.id) == false)
    }

    @Test func aNetOfZeroIsEnoughWhenDebtsAreSimplified() throws {
        let fixture = try Fixture(simplifies: true)
        try addCrossingDebts(fixture)
        try fixture.services.groups.removeMember(fixture.me.id, from: fixture.group.id)
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.memberIDs.contains(fixture.me.id) == false)
    }

    @Test func deletingAGroupRemovesItsContentFromQueries() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        try fixture.services.comments.add(ExpenseComment(
            groupID: fixture.group.id, expenseID: expense.id, authorID: fixture.me.id, text: "hi"
        ))
        try fixture.services.groups.delete(id: fixture.group.id)
        #expect(try fixture.services.groups.group(id: fixture.group.id) == nil)
        #expect(try fixture.services.groups.groups(includeArchived: true).isEmpty)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).isEmpty)
        #expect(try fixture.services.activity.entries(limit: 50).isEmpty)
        #expect(try fixture.services.comments.comments(on: expense.id).isEmpty)
    }

    @Test func updatingAnUnknownGroupThrows() throws {
        let fixture = try Fixture()
        #expect(throws: DataError.self) {
            try fixture.services.groups.update(SplitGroup(name: "Nope", currencyCode: "USD"))
        }
    }

    @Test func groupBalancesComeFromTheLedger() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        let balances = try fixture.services.groups.balances(for: fixture.group.id)
        #expect(balances.net(for: fixture.me.id) == [usdAmount(2000)])
        #expect(balances.net(for: fixture.sam.id) == [usdAmount(-1000)])
        #expect(!balances.isSettled)
        #expect(balances.suggestedSettlements.count == 2)
    }

    @Test func suggestedSettlementsFollowTheSimplifyToggle() throws {
        let simple = try Fixture(simplifies: true)
        let direct = try Fixture(simplifies: false)
        for fixture in [simple, direct] {
            try fixture.addExpense("A", cents: 3000, paidBy: fixture.me)
            try fixture.addExpense("B", cents: 3000, paidBy: fixture.sam, splitBetween: [fixture.sam.id, fixture.priya.id])
        }
        let simplified = try simple.services.groups.balances(for: simple.group.id)
        let raw = try direct.services.groups.balances(for: direct.group.id)
        #expect(simplified.suggestedSettlements.count <= raw.suggestedSettlements.count)
        #expect(simplified.suggestedSettlements == simplified.ledger.simplifiedDebts)
        #expect(raw.suggestedSettlements == raw.ledger.debts)
    }

    @Test func deletedExpensesDoNotCountTowardBalances() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense(cents: 3000)
        try fixture.services.expenses.delete(id: expense.id)
        #expect(try fixture.services.groups.balances(for: fixture.group.id).isSettled)
    }

    @Test func balancesOfAnUnknownGroupThrow() throws {
        let fixture = try Fixture()
        #expect(throws: DataError.self) { try fixture.services.groups.balances(for: GroupID()) }
    }

    @Test func friendBalanceSumsEveryGroupYouShare() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        let second = SplitGroup(name: "Trip", currencyCode: "USD", memberIDs: [fixture.me.id, fixture.sam.id])
        try fixture.services.groups.create(second)
        try fixture.services.expenses.add(Expense(
            groupID: second.id, title: "Taxi", total: usdAmount(1000), date: fixture.clock.start,
            paidBy: fixture.sam.id, split: .equal(participants: [fixture.me.id, fixture.sam.id])
        ))
        let balance = try fixture.services.people.friendBalance(with: fixture.sam.id)
        #expect(balance.total == [usdAmount(1000)])
        #expect(balance.byGroup.count == 2)
        #expect(Set(balance.byGroup.map(\.groupID)) == [fixture.group.id, second.id])
    }

    @Test func aFriendTotalAcrossGroupsCanAlwaysBeNegated() throws {
        let fixture = try Fixture()
        let huge = usdAmount(1 << 62)
        for group in [fixture.group.id, try makeSecondGroup(fixture)] {
            try fixture.services.expenses.add(Expense(
                groupID: group, title: "Huge", total: huge, date: fixture.clock.start,
                paidBy: fixture.sam.id, split: .exact(amounts: [fixture.me.id: huge])
            ))
        }
        let balance = try fixture.services.people.friendBalance(with: fixture.sam.id)
        #expect(balance.total == [usdAmount(-Int64.max)])
        #expect(BalanceTotals(amounts: balance.total).youOwe == [usdAmount(Int64.max)])
    }

    private func makeSecondGroup(_ fixture: Fixture) throws -> GroupID {
        let second = SplitGroup(name: "Trip", currencyCode: "USD", memberIDs: [fixture.me.id, fixture.sam.id])
        try fixture.services.groups.create(second)
        return second.id
    }

    /// You owe Sam 10.00 and Sam owes Priya 10.00, so simplifying has you pay Priya.
    private func addChainOfDebts(_ fixture: Fixture) throws {
        try fixture.addExpense(cents: 1000, paidBy: fixture.sam, splitBetween: [fixture.me.id])
        try fixture.addExpense(cents: 1000, paidBy: fixture.priya, splitBetween: [fixture.sam.id])
    }

    @Test func friendBalancesFollowASimplifiedGroup() throws {
        let fixture = try Fixture(simplifies: true)
        try addChainOfDebts(fixture)
        #expect(try fixture.services.people.friendBalance(with: fixture.sam.id).isSettled)
        #expect(try fixture.services.people.friendBalance(with: fixture.priya.id).total == [usdAmount(-1000)])
    }

    @Test func friendBalancesKeepDirectDebtsWithoutSimplifying() throws {
        let fixture = try Fixture(simplifies: false)
        try addChainOfDebts(fixture)
        #expect(try fixture.services.people.friendBalance(with: fixture.sam.id).total == [usdAmount(-1000)])
        #expect(try fixture.services.people.friendBalance(with: fixture.priya.id).isSettled)
    }

    @Test func nobodyOwesAnybodyAfterASimplifiedSettle() throws {
        let fixture = try Fixture(simplifies: true)
        try addChainOfDebts(fixture)
        let debts = try fixture.services.groups.balances(for: fixture.group.id).suggestedSettlements
        #expect(debts.count == 1)
        for debt in debts { try fixture.services.payments.settle(debt, in: fixture.group.id, date: fixture.clock.start, note: "") }
        #expect(try fixture.services.groups.balances(for: fixture.group.id).isSettled)
        #expect(try fixture.services.people.friendBalances().allSatisfy(\.isSettled))
    }

    @Test func friendBalanceIsNegativeWhenYouOwe() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, paidBy: fixture.sam, splitBetween: [fixture.me.id, fixture.sam.id])
        #expect(try fixture.services.people.friendBalance(with: fixture.sam.id).total == [usdAmount(-1500)])
    }

    @Test func friendBalanceKeepsCurrenciesApart() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        try fixture.services.expenses.add(Expense(
            groupID: fixture.group.id, title: "Cafe", total: Money(minorUnits: 600, currencyCode: "EUR"),
            date: fixture.clock.start, paidBy: fixture.sam.id,
            split: .equal(participants: [fixture.me.id, fixture.sam.id])
        ))
        let balance = try fixture.services.people.friendBalance(with: fixture.sam.id)
        #expect(balance.total == [Money(minorUnits: -300, currencyCode: "EUR"), usdAmount(1500)])
    }

    @Test func friendsYouAreSquareWithHaveNoBalance() throws {
        let fixture = try Fixture()
        let balance = try fixture.services.people.friendBalance(with: fixture.sam.id)
        #expect(balance.isSettled)
        #expect(balance.byGroup.isEmpty)
        #expect(try fixture.services.people.friendBalances().isEmpty)
    }

    @Test func friendBalancesAreSortedByFriendName() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        #expect(try fixture.services.people.friendBalances().map(\.friendID) == [fixture.priya.id, fixture.sam.id])
    }
}
