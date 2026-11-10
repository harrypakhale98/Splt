import Foundation
import SpltCore
import Testing
@testable import Splt

/// Unusual but real situations, run through the repositories the screens use.
@MainActor
@Suite("Edge cases")
struct EdgeCaseTests {
    private func money(_ units: Int64, _ code: String) -> Money {
        Money(minorUnits: units, currencyCode: code)
    }

    private func group(
        _ name: String, currency: String, members: [Person], in services: DataServices
    ) throws -> SplitGroup {
        let value = SplitGroup(name: name, currencyCode: currency, memberIDs: members.map(\.id))
        try services.groups.create(value)
        return value
    }

    private func net(_ person: Person, in group: SplitGroup, _ services: DataServices) throws -> [Money] {
        try services.groups.balances(for: group.id).net(for: person.id)
    }

    @Test func aZeroAmountExpenseChangesNoBalance() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Nothing", cents: 0)
        let balances = try fixture.services.groups.balances(for: fixture.group.id)
        #expect(balances.isSettled)
        #expect(balances.suggestedSettlements.isEmpty)
    }

    @Test func aHugeAmountSplitsAndStillAddsUp() throws {
        let fixture = try Fixture()
        let cents: Int64 = 900_000_000_000_000
        try fixture.addExpense("Yacht", cents: cents)

        let balances = try fixture.services.groups.balances(for: fixture.group.id)
        let owed = try #require(balances.net(for: fixture.me.id).first)
        let sam = try #require(balances.net(for: fixture.sam.id).first)
        let priya = try #require(balances.net(for: fixture.priya.id).first)
        #expect(owed.minorUnits == cents - cents / 3)
        #expect(owed.minorUnits + sam.minorUnits + priya.minorUnits == 0)
    }

    @Test func yenHasNoFractionAndSplitsInWholeYen() throws {
        let services = try DataServices.inMemory()
        let me = try services.people.ensureMe(name: "Me")
        let ken = Person(name: "Ken", avatarSeed: 1)
        let mio = Person(name: "Mio", avatarSeed: 2)
        try services.people.add(ken)
        try services.people.add(mio)
        let trip = try group("Tokyo", currency: "JPY", members: [me, ken, mio], in: services)

        let ramen = Expense(
            groupID: trip.id, title: "Ramen", total: money(1000, "JPY"), date: Date(),
            paidBy: me.id, split: .equal(participants: [me.id, ken.id, mio.id])
        )
        try services.expenses.add(ramen)

        let mine = try #require(try net(me, in: trip, services).first)
        let kens = try #require(try net(ken, in: trip, services).first)
        let mios = try #require(try net(mio, in: trip, services).first)
        #expect(mine.exponent == 0)
        #expect(mine.minorUnits + kens.minorUnits + mios.minorUnits == 0)
        #expect([333, 334].contains(-kens.minorUnits))
        #expect([333, 334].contains(-mios.minorUnits))
        #expect(mine.minorUnits == 666 || mine.minorUnits == 667)
    }

    @Test func dinarsKeepThreeDecimals() throws {
        let services = try DataServices.inMemory()
        let me = try services.people.ensureMe(name: "Me")
        let sara = Person(name: "Sara", avatarSeed: 1)
        try services.people.add(sara)
        let kuwait = try group("Kuwait", currency: "KWD", members: [me, sara], in: services)

        let tea = Expense(
            groupID: kuwait.id, title: "Tea", total: money(12_345, "KWD"), date: Date(),
            paidBy: me.id, split: .equal(participants: [me.id, sara.id])
        )
        try services.expenses.add(tea)

        let owed = try #require(try net(me, in: kuwait, services).first)
        let saras = try #require(try net(sara, in: kuwait, services).first)
        #expect(owed.exponent == 3)
        #expect(owed.minorUnits + saras.minorUnits == 0)
        #expect(owed.minorUnits == 6_172 || owed.minorUnits == 6_173)
    }

    @Test func aGroupOfTwelveSplitsToTheLastUnit() throws {
        let services = try DataServices.inMemory()
        let me = try services.people.ensureMe(name: "Me")
        let others = (1...11).map { Person(name: "Guest \($0)", avatarSeed: $0) }
        for person in others { try services.people.add(person) }
        let members = [me] + others
        let party = try group("Party", currency: "USD", members: members, in: services)

        let bill = Expense(
            groupID: party.id, title: "Venue", total: money(100_001, "USD"), date: Date(),
            paidBy: me.id, split: .equal(participants: Set(members.map(\.id)))
        )
        try services.expenses.add(bill)

        let all = try members.map { try #require(try net($0, in: party, services).first).minorUnits }
        #expect(all.reduce(0, +) == 0)
        let shares = all.dropFirst().map { -$0 }
        #expect(shares.allSatisfy { $0 == 8_333 || $0 == 8_334 })

        let balances = try services.groups.balances(for: party.id)
        #expect(balances.suggestedSettlements.count == 11)
    }

    @Test func aDeletedFriendDoesNotBreakTheGroup() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        try fixture.services.removePerson(fixture.sam.id)

        let balances = try fixture.services.groups.balances(for: fixture.group.id)
        #expect(balances.net(for: fixture.me.id).first?.minorUnits == 2000)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id, includeDeleted: false).count == 1)

        let detail = GroupDetailViewModel(groupID: fixture.group.id, services: fixture.services)
        #expect(detail.group != nil)
        #expect(detail.name(of: fixture.sam.id) == "Someone")
        fixture.services.friendsStore.refresh()
        #expect(!fixture.services.friendsStore.summaries.contains { $0.id == fixture.sam.id })
    }

    @Test func aForeignExpenseSavesWhileOffline() throws {
        let fixture = try Fixture()
        let hotel = Expense(
            groupID: fixture.group.id, title: "Hotel", total: money(50_000, "EUR"), date: Date(),
            paidBy: fixture.me.id, split: .equal(participants: fixture.everyone)
        )
        try fixture.services.expenses.add(hotel)

        let balances = try fixture.services.groups.balances(for: fixture.group.id)
        #expect(balances.net(for: fixture.me.id).first?.currencyCode == "EUR")
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id, includeDeleted: false).count == 1)
    }

    @Test func anEmptyStoreShowsNothingAndFailsNowhere() throws {
        let services = try DataServices.inMemory()
        services.groupsStore.refresh()
        services.friendsStore.refresh()
        #expect(services.groupsStore.summaries.isEmpty)
        #expect(services.friendsStore.summaries.isEmpty)
        #expect(try services.groups.groups(includeArchived: true).isEmpty)
        #expect(try services.people.friendBalances().isEmpty)
        #expect(try services.search.search("anything", limit: 10).isEmpty)
    }

    @Test func aMemberWithABalanceCannotLeaveUntilSettled() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        #expect(throws: DataError.self) {
            try fixture.services.groups.removeMember(fixture.sam.id, from: fixture.group.id)
        }

        let debt = Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usdAmount(1000))
        try fixture.services.payments.settle(debt, in: fixture.group.id, date: Date(), note: "")
        try fixture.services.groups.removeMember(fixture.sam.id, from: fixture.group.id)

        let members = try #require(try fixture.services.groups.group(id: fixture.group.id)).memberIDs
        #expect(!members.contains(fixture.sam.id))
    }

    @Test func partialPaymentsAddUpAndSettleTheRest() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let owed = Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usdAmount(300))
        try fixture.services.payments.settle(owed, in: fixture.group.id, date: Date(), note: "")
        try fixture.services.payments.settle(owed, in: fixture.group.id, date: Date(), note: "")

        var remaining = try net(fixture.sam, in: fixture.group, fixture.services)
        #expect(remaining == [usdAmount(-400)])

        let rest = Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usdAmount(400))
        try fixture.services.payments.settle(rest, in: fixture.group.id, date: Date(), note: "")
        remaining = try net(fixture.sam, in: fixture.group, fixture.services)
        #expect(remaining.isEmpty)
    }

    @Test func undoingAPaymentTwiceChangesNothingTheSecondTime() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let debt = Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usdAmount(1000))
        let payment = try fixture.services.payments.settle(debt, in: fixture.group.id, date: Date(), note: "")

        try fixture.services.payments.undo(id: payment.id)
        let afterFirst = try net(fixture.sam, in: fixture.group, fixture.services)
        try fixture.services.payments.undo(id: payment.id)
        let afterSecond = try net(fixture.sam, in: fixture.group, fixture.services)
        #expect(afterFirst == [usdAmount(-1000)])
        #expect(afterSecond == afterFirst)

        try fixture.services.payments.restore(id: payment.id)
        try fixture.services.payments.restore(id: payment.id)
        #expect(try net(fixture.sam, in: fixture.group, fixture.services).isEmpty)
    }
}
