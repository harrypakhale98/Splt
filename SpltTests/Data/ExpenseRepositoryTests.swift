import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Expense repository")
struct ExpenseRepositoryTests {
    @Test func addsAndReadsAnExpenseWithItsExtras() throws {
        let fixture = try Fixture()
        let expense = fixture.expense("Pizza")
        let extras = ExpenseExtras(
            receiptFileName: "pizza.jpg", location: ExpenseLocation(name: "Luigi's", latitude: 40.7, longitude: -74)
        )
        try fixture.services.expenses.add(expense, extras: extras)
        #expect(try fixture.services.expenses.expense(id: expense.id) == expense)
        let details = try #require(try fixture.services.expenses.details(id: expense.id))
        #expect(details.extras == extras)
        #expect(details.createdBy == fixture.me.id)
        #expect(details.history.isEmpty)
    }

    @Test func listsNewestFirst() throws {
        let fixture = try Fixture()
        let old = try fixture.addExpense("Old", date: fixture.clock.start)
        let new = try fixture.addExpense("New", date: fixture.clock.start.addingTimeInterval(86_400))
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).map(\.id) == [new.id, old.id])
    }

    @Test func rejectsAnInvalidExpense() throws {
        let fixture = try Fixture()
        var bad = fixture.expense()
        bad.payers = [fixture.me.id: usdAmount(100)]
        #expect(throws: DataError.invalidExpense(.payersDoNotMatchTotal(expected: usdAmount(3000), actual: usdAmount(100)))) {
            try fixture.services.expenses.add(bad)
        }
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).isEmpty)
    }

    @Test func rejectsExpensesWithoutAGroupOrInAnUnknownOne() throws {
        let fixture = try Fixture()
        var loose = fixture.expense()
        loose.groupID = nil
        #expect(throws: DataError.missingGroup) { try fixture.services.expenses.add(loose) }
        var stray = fixture.expense()
        stray.groupID = GroupID()
        #expect(throws: DataError.self) { try fixture.services.expenses.add(stray) }
    }

    @Test func rejectsTheSameIDTwice() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        #expect(throws: DataError.alreadyExists("expense \(expense.id)")) { try fixture.services.expenses.add(expense) }
    }

    @Test func addingWritesAnActivityEntryForTheCurrentUser() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Pizza")
        let entry = try #require(try fixture.services.activity.entries(in: fixture.group.id, limit: 1).first)
        #expect(entry.actorID == fixture.me.id)
        #expect(entry.event == .expenseAdded(ExpenseReference(id: expense.id, title: "Pizza", amount: usdAmount(3000))))
    }

    @Test func editingStoresTheChangeLogsItAndKeepsHistory() throws {
        let fixture = try Fixture()
        var expense = try fixture.addExpense("Dinner", cents: 3000)
        expense.title = "Team dinner"
        expense.total = usdAmount(4500)
        expense.payers = [fixture.me.id: usdAmount(4500)]
        try fixture.services.expenses.update(expense)

        #expect(try fixture.services.expenses.expense(id: expense.id) == expense)
        let history = try #require(try fixture.services.expenses.details(id: expense.id)).history
        #expect(history.count == 1)
        #expect(history[0].changedFields == [.title, .total, .payers])
        #expect(history[0].previousTitle == "Dinner")
        #expect(history[0].previousTotal == usdAmount(3000))
        #expect(history[0].editor == fixture.me.id)
        let latest = try #require(try fixture.services.activity.entries(in: fixture.group.id, limit: 1).first)
        #expect(latest.event.kind == .expenseEdited)
    }

    @Test func savingWithoutChangesDoesNothing() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        let before = try fixture.services.activity.entries(in: fixture.group.id, limit: 50).count
        try fixture.services.expenses.update(expense)
        #expect(try fixture.services.activity.entries(in: fixture.group.id, limit: 50).count == before)
        #expect(try fixture.services.expenses.details(id: expense.id)?.history.isEmpty == true)
    }

    @Test func extrasChangeAloneIsAnEdit() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        try fixture.services.expenses.update(expense, extras: ExpenseExtras(receiptFileName: "r.jpg"))
        let details = try #require(try fixture.services.expenses.details(id: expense.id))
        #expect(details.extras.receiptFileName == "r.jpg")
        #expect(details.history.map(\.changedFields) == [[.receipt]])
    }

    @Test func nilExtrasLeaveTheExistingOnesAlone() throws {
        let fixture = try Fixture()
        var expense = fixture.expense()
        try fixture.services.expenses.add(expense, extras: ExpenseExtras(receiptFileName: "r.jpg"))
        expense.note = "with a note"
        try fixture.services.expenses.update(expense, extras: nil)
        #expect(try fixture.services.expenses.details(id: expense.id)?.extras.receiptFileName == "r.jpg")
    }

    @Test func editingChangesBalances() throws {
        let fixture = try Fixture()
        var expense = try fixture.addExpense(cents: 3000)
        expense.total = usdAmount(6000)
        expense.payers = [fixture.me.id: usdAmount(6000)]
        try fixture.services.expenses.update(expense)
        let balances = try fixture.services.groups.balances(for: fixture.group.id)
        #expect(balances.net(for: fixture.me.id) == [usdAmount(4000)])
    }

    @Test func editingAnUnknownOrDeletedExpenseThrows() throws {
        let fixture = try Fixture()
        #expect(throws: DataError.self) { try fixture.services.expenses.update(fixture.expense()) }
        let expense = try fixture.addExpense()
        try fixture.services.expenses.delete(id: expense.id)
        #expect(throws: DataError.self) { try fixture.services.expenses.update(expense) }
    }

    @Test func deleteIsSoftAndLogged() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        try fixture.services.expenses.delete(id: expense.id)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).isEmpty)
        let all = try fixture.services.expenses.expenses(in: fixture.group.id, includeDeleted: true)
        #expect(all.count == 1)
        #expect(all[0].isDeleted)
        let latest = try #require(try fixture.services.activity.entries(in: fixture.group.id, limit: 1).first)
        #expect(latest.event.kind == .expenseDeleted)
    }

    @Test func deletingTwiceLogsOnce() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        try fixture.services.expenses.delete(id: expense.id)
        try fixture.services.expenses.delete(id: expense.id)
        let deletions = try fixture.services.activity.entries(in: fixture.group.id, limit: 50)
            .filter { $0.event.kind == .expenseDeleted }
        #expect(deletions.count == 1)
    }

    @Test func undoingADeleteBringsTheExpenseAndItsBalanceBack() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense(cents: 3000)
        try fixture.services.expenses.delete(id: expense.id)
        try fixture.services.expenses.restore(id: expense.id)
        let restored = try #require(try fixture.services.expenses.expense(id: expense.id))
        #expect(!restored.isDeleted)
        #expect(try fixture.services.groups.balances(for: fixture.group.id).net(for: fixture.me.id) == [usdAmount(2000)])
        let latest = try #require(try fixture.services.activity.entries(in: fixture.group.id, limit: 1).first)
        #expect(latest.event.kind == .expenseRestored)
    }

    @Test func deleteAndRestoreAreTrackedForSyncAsSaves() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        let tracker = fixture.services.makeChangeTracker()
        let record = try #require(try ExpenseRecord.find(recordName: expense.id.description, in: fixture.services.container.mainContext))
        try tracker.markSynced(recordType: .expense, recordName: record.recordName, sentModifiedAt: .distantFuture, systemFields: Data([1]))
        try fixture.services.expenses.delete(id: expense.id)
        #expect(record.pendingOperation == .save)
        #expect(record.deletedAt != nil)
        let deletedAt = try #require(record.deletedAt)
        try fixture.services.expenses.restore(id: expense.id)
        #expect(record.deletedAt == nil)
        #expect(record.modifiedAt > deletedAt)
    }

    @Test func findsAnExpenseWithTheSameAmountTitleAndDay() throws {
        let fixture = try Fixture()
        let existing = try fixture.addExpense("Dinner at Luigi's", cents: 4200)
        let candidate = fixture.expense("dinner at luigi's", cents: 4200, date: fixture.clock.start.addingTimeInterval(3_600))
        #expect(try fixture.services.expenses.duplicates(of: candidate).map(\.id) == [existing.id])
    }

    @Test func similarTitlesMatchWhenOneContainsTheOther() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 4200)
        let candidate = fixture.expense("Dinner with the team", cents: 4200)
        #expect(try fixture.services.expenses.duplicates(of: candidate).count == 1)
    }

    @Test func differentAmountsTitlesOrFarApartDatesAreNotDuplicates() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 4200)
        #expect(try fixture.services.expenses.duplicates(of: fixture.expense("Dinner", cents: 4201)).isEmpty)
        #expect(try fixture.services.expenses.duplicates(of: fixture.expense("Taxi", cents: 4200)).isEmpty)
        let later = fixture.expense("Dinner", cents: 4200, date: fixture.clock.start.addingTimeInterval(10 * 86_400))
        #expect(try fixture.services.expenses.duplicates(of: later).isEmpty)
        #expect(try fixture.services.expenses.duplicates(of: later, withinDays: 14).count == 1)
    }

    @Test func anExpenseIsNotItsOwnDuplicateAndDeletedOnesAreIgnored() throws {
        let fixture = try Fixture()
        let first = try fixture.addExpense("Dinner", cents: 4200)
        #expect(try fixture.services.expenses.duplicates(of: first).isEmpty)
        let second = try fixture.addExpense("Dinner", cents: 4200)
        try fixture.services.expenses.delete(id: second.id)
        #expect(try fixture.services.expenses.duplicates(of: first).isEmpty)
    }

    @Test func duplicatesStayInsideTheirGroup() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 4200)
        var elsewhere = fixture.expense("Dinner", cents: 4200)
        elsewhere.groupID = GroupID()
        #expect(try fixture.services.expenses.duplicates(of: elsewhere).isEmpty)
    }

    @Test func sharedExpensesAreTheOnesYouAndAFriendBothTakePartIn() throws {
        let fixture = try Fixture()
        let both = try fixture.addExpense("With Sam", splitBetween: [fixture.me.id, fixture.sam.id])
        try fixture.addExpense("Without Sam", splitBetween: [fixture.me.id, fixture.priya.id])
        try fixture.addExpense("Sam and Priya only", paidBy: fixture.sam, splitBetween: [fixture.sam.id, fixture.priya.id])
        #expect(try fixture.services.expenses.sharedExpenses(with: fixture.sam.id).map(\.id) == [both.id])
    }
}
