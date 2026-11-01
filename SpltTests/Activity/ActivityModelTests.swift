import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Activity model")
struct ActivityModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Dinner added, then a payment from Sam, in one group.
    private func scene() throws -> (fixture: Fixture, model: ActivityModel, payment: Payment) {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let payment = Payment(groupID: fixture.group.id, payer: fixture.sam.id, receiver: fixture.me.id, amount: usdAmount(1000), date: fixture.clock.start)
        try fixture.services.payments.record(payment)
        return (fixture, ActivityModel(services: fixture.services, calendar: calendar), payment)
    }

    @Test func listsNewestFirstWithText() throws {
        let (_, model, _) = try scene()
        let kinds = model.visibleEntries.map(\.event.kind)
        #expect(kinds.first == .paymentRecorded)
        #expect(kinds.contains(.expenseAdded))
        let payment = try #require(model.visibleEntries.first)
        #expect(model.text(for: payment, locale: Locale(identifier: "en_US")) == "Sam paid You $10.00")
    }

    @Test func groupsEntriesByDay() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        fixture.clock.advance(by: 2 * 86_400)
        try fixture.addExpense("Taxi", cents: 900)
        try fixture.addExpense("Snacks", cents: 300)
        let model = ActivityModel(services: fixture.services, calendar: calendar)
        let sections = model.sections
        #expect(sections.count == 2)
        #expect(sections[0].day > sections[1].day)
        #expect(sections[0].entries.count == 2)
        #expect(sections[1].entries.contains { $0.event.kind == .expenseAdded })
    }

    @Test func titlesTodayAndYesterday() throws {
        let fixture = try Fixture()
        let model = ActivityModel(services: fixture.services, calendar: calendar)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let today = ActivityModel.DaySection(day: calendar.startOfDay(for: now), entries: [])
        let yesterday = ActivityModel.DaySection(day: calendar.startOfDay(for: now.addingTimeInterval(-86_400)), entries: [])
        let older = ActivityModel.DaySection(day: calendar.startOfDay(for: now.addingTimeInterval(-5 * 86_400)), entries: [])
        let english = Locale(identifier: "en_US")
        #expect(model.title(for: today, now: now, locale: english) == "Today")
        #expect(model.title(for: yesterday, now: now, locale: english) == "Yesterday")
        #expect(model.title(for: older, now: now, locale: english).contains("2025"))
    }

    @Test func filtersByTypeAndGroup() throws {
        let (fixture, model, _) = try scene()
        model.typeFilter = .payments
        #expect(model.visibleEntries.allSatisfy { $0.event.kind == .paymentRecorded })
        #expect(!model.visibleEntries.isEmpty)
        model.typeFilter = .comments
        #expect(model.visibleEntries.isEmpty)
        #expect(model.isFiltering)
        model.clearFilters()
        model.groupFilter = GroupID()
        #expect(model.visibleEntries.isEmpty)
        model.groupFilter = fixture.group.id
        #expect(!model.visibleEntries.isEmpty)
        #expect(model.filterGroups.map(\.id) == [fixture.group.id])
    }

    @Test func everyKindBelongsToATypeFilter() {
        for kind in ActivityKind.allCases {
            let owners = ActivityTypeFilter.allCases.filter { $0 != .all && $0.includes(kind) }
            #expect(owners.count == 1, "\(kind) should be in exactly one filter")
            #expect(ActivityTypeFilter.all.includes(kind))
        }
    }

    @Test func tracksAndClearsUnreadEntries() throws {
        let (fixture, model, _) = try scene()
        let unread = model.unreadCount
        #expect(unread > 0)
        let store = UnreadActivityStore(services: fixture.services)
        #expect(store.count == unread)

        let first = try #require(model.visibleEntries.first)
        model.markRead(first)
        #expect(model.unreadCount == unread - 1)
        model.markAllRead()
        #expect(model.unreadCount == 0)
        store.refresh()
        #expect(store.count == 0)
    }

    @Test func onlyTheNewestEventAboutAPaymentOffersAnAction() throws {
        let (fixture, model, payment) = try scene()
        let recorded = try #require(model.visibleEntries.first { $0.event.kind == .paymentRecorded })
        #expect(model.paymentActions[recorded.id] == .undo)

        model.perform(.undo, on: recorded)
        #expect(try fixture.services.payments.payment(id: payment.id)?.isDeleted == true)
        let undone = try #require(model.visibleEntries.first { $0.event.kind == .paymentUndone })
        #expect(model.paymentActions[undone.id] == .restore)
        #expect(model.paymentActions[recorded.id] == nil)

        model.perform(.restore, on: undone)
        #expect(try fixture.services.payments.payment(id: payment.id)?.isDeleted == false)
        let newest = try #require(model.visibleEntries.first)
        #expect(model.paymentActions[newest.id] == .undo)
    }

    @Test func undoingBringsTheDebtBack() throws {
        let (fixture, model, _) = try scene()
        #expect(try fixture.services.people.friendBalance(with: fixture.sam.id).isSettled)
        let recorded = try #require(model.visibleEntries.first { $0.event.kind == .paymentRecorded })
        model.perform(.undo, on: recorded)
        #expect(try fixture.services.people.friendBalance(with: fixture.sam.id).total == [usdAmount(1000)])
    }
}

@Suite("Activity destinations")
struct ActivityDestinationTests {
    private let me = PersonID()
    private let sam = PersonID()
    private let group = SplitGroup(name: "Flat", currencyCode: "USD")

    private func entry(_ event: ActivityEvent, in group: SplitGroup? = nil) -> ActivityEntry {
        ActivityEntry(groupID: (group ?? self.group).id, event: event)
    }

    private func route(_ entry: ActivityEntry, groups: [SplitGroup]? = nil) -> Route? {
        ActivityDestination.route(for: entry, me: me, groups: Dictionary(uniqueKeysWithValues: (groups ?? [group]).map { ($0.id, $0) }))
    }

    @Test func expenseEventsOpenTheExpense() {
        let reference = ExpenseReference(id: ExpenseID(), title: "Dinner", amount: usdAmount(100))
        #expect(route(entry(.expenseAdded(reference))) == .expense(reference.id.rawValue))
        #expect(route(entry(.expenseEdited(reference))) == .expense(reference.id.rawValue))
        #expect(route(entry(.commentAdded(expense: reference, text: "hi"))) == .expense(reference.id.rawValue))
    }

    @Test func deletedExpensesOpenTheGroup() {
        let reference = ExpenseReference(id: ExpenseID(), title: "Dinner", amount: usdAmount(100))
        #expect(route(entry(.expenseDeleted(reference))) == .group(group.id.rawValue))
    }

    @Test func paymentsOpenTheOtherPerson() {
        let toMe = PaymentReference(id: PaymentID(), payer: sam, receiver: me, amount: usdAmount(100))
        let fromMe = PaymentReference(id: PaymentID(), payer: me, receiver: sam, amount: usdAmount(100))
        #expect(route(entry(.paymentRecorded(toMe))) == .friend(sam.rawValue))
        #expect(route(entry(.paymentUndone(fromMe))) == .friend(sam.rawValue))
    }

    @Test func paymentsBetweenOthersOpenTheGroup() {
        let other = PaymentReference(id: PaymentID(), payer: sam, receiver: PersonID(), amount: usdAmount(100))
        #expect(route(entry(.paymentRecorded(other))) == .group(group.id.rawValue))
    }

    @Test func memberEventsOpenThatPerson() {
        #expect(route(entry(.memberAdded(sam))) == .friend(sam.rawValue))
        #expect(route(entry(.memberAdded(me))) == .group(group.id.rawValue))
    }

    @Test func groupEventsOpenTheGroup() {
        #expect(route(entry(.groupCreated(name: "Flat"))) == .group(group.id.rawValue))
        #expect(route(entry(.groupRenamed(from: "a", to: "b"))) == .group(group.id.rawValue))
        #expect(route(entry(.expensesImported(expenses: 1, payments: 0))) == .group(group.id.rawValue))
    }

    @Test func hiddenFriendGroupsOpenTheFriend() {
        let direct = SplitGroup(name: "Sam", currencyCode: "USD", kind: .friend, memberIDs: [me, sam])
        #expect(route(entry(.groupArchived, in: direct), groups: [direct]) == .friend(sam.rawValue))
    }

    @Test func entriesWithoutAGroupGoNowhere() {
        let loose = ActivityEntry(event: .groupArchived)
        #expect(ActivityDestination.route(for: loose, me: me, groups: [:]) == nil)
    }
}
