import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Expense detail")
@MainActor
struct ExpenseDetailModelTests {
    private let us = Locale(identifier: "en_US")

    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    @Test func listsPayersAndSharesByName() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Dinner", cents: 3000, paidBy: fixture.sam)
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: us)

        #expect(model.expense?.title == "Dinner")
        #expect(model.payerLines.map(\.name) == ["Sam"])
        #expect(model.shareLines.count == 3)
        #expect(model.shareLines.allSatisfy { $0.share == usd(1000) })
        #expect(model.shareLines.contains { $0.name == "You" })
        #expect(model.group?.name == "Flat")
    }

    @Test func shareLinesReadNaturallyForVoiceOver() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Dinner", cents: 3000)
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: us)
        let sam = try #require(model.shareLines.first { $0.name == "Sam" })
        #expect(sam.spokenText(locale: us) == "Sam owes $10.00")
    }

    @Test func itemizedSharesIncludeTheirBreakdown() throws {
        let fixture = try Fixture()
        let split = SplitDefinition.itemized(ItemizedSplit(
            items: [
                SplitItem(name: "Pizza", amount: usd(2000), assignees: [fixture.me.id]),
                SplitItem(name: "Beer", amount: usd(1000), assignees: [fixture.sam.id])
            ],
            tax: usd(300)
        ))
        let expense = Expense(
            groupID: fixture.group.id, title: "Night", total: usd(3300), date: fixture.clock.start,
            paidBy: fixture.me.id, split: split
        )
        try fixture.services.expenses.add(expense)
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: us)
        let mine = try #require(model.shareLines.first { $0.name == "You" })
        #expect(mine.breakdown?.items == usd(2000))
        let spoken = mine.spokenText(locale: us)
        #expect(spoken.hasPrefix("You owe $22.00"))
        #expect(spoken.contains("tax"))
    }

    @Test func deleteCanBeUndone() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: us)
        #expect(!model.isDeleted)

        model.delete()
        #expect(model.isDeleted)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).isEmpty)

        model.undoDelete()
        #expect(!model.isDeleted)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 1)
    }

    @Test func commentsAndReactionsWork() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense()
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: us)

        model.addComment("   ")
        #expect(model.comments.isEmpty)
        model.addComment("  Great dinner  ")
        let comment = try #require(model.comments.first)
        #expect(comment.text == "Great dinner")
        #expect(comment.authorID == fixture.me.id)

        model.toggleReaction("\u{1F44D}", on: comment)
        #expect(model.comments.first?.reactions.count == 1)
        model.toggleReaction("\u{1F44D}", on: model.comments[0])
        #expect(model.comments.first?.reactions.isEmpty == true)

        model.deleteComment(model.comments[0])
        #expect(model.comments.isEmpty)
    }

    @Test func historyAndNamesComeFromTheEdits() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Taxi", cents: 2000)
        var edited = expense
        edited.title = "Airport taxi"
        try fixture.services.expenses.update(edited)
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: us)
        let history = try #require(model.details?.history)
        #expect(history.count == 1)
        #expect(model.name(for: try #require(history[0].editor)) == "You")
        #expect(ExpenseField.total.displayName == "amount")
    }

    @Test func unknownExpensesFail() throws {
        let fixture = try Fixture()
        let model = ExpenseDetailModel(expenseID: ExpenseID(), services: fixture.services, locale: us)
        #expect(model.failed)
    }

    @Test func sharedTextListsEveryone() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Dinner", cents: 3000)
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: us)
        let text = model.shareText
        #expect(text.hasPrefix("Dinner\n$30.00,"))
        #expect(text.contains("Paid by Me"))
        #expect(text.contains("  Sam: $10.00"))
        #expect(text.contains("Flat"))
    }

    @Test func sharedTextSaysARefundIsOne() throws {
        let fixture = try Fixture()
        let refund = Expense(
            groupID: fixture.group.id, title: "Hotel", total: usd(-3000), date: fixture.clock.start,
            paidBy: fixture.me.id, split: .equal(participants: fixture.everyone)
        )
        try fixture.services.expenses.add(refund)
        let model = ExpenseDetailModel(expenseID: refund.id, services: fixture.services, locale: us)
        let text = model.shareText
        #expect(text.hasPrefix("Hotel\nRefund, -$30.00,"))
        #expect(text.contains("  Sam: -$10.00"))
    }

    @Test func historyKeepsTheSignOfARefundsOldTotal() {
        let refund = ExpenseEditEntry(date: Date(), changedFields: [.total], previousTotal: usd(-3000))
        #expect(ExpenseHistoryBuilder.previousValues(of: refund, locale: us) == "Amount was -$30.00")
        let purchase = ExpenseEditEntry(date: Date(), changedFields: [.total, .title], previousTitle: "Lunch", previousTotal: usd(3000))
        #expect(ExpenseHistoryBuilder.previousValues(of: purchase, locale: us) == "Title was Lunch. Amount was $30.00")
        #expect(ExpenseHistoryBuilder.previousValues(of: ExpenseEditEntry(date: Date(), changedFields: [.note]), locale: us) == nil)
    }

    @Test func duplicatingMakesADraft() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Dinner", cents: 3000)
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: us)
        let draft = try #require(model.duplicateDraft)
        #expect(draft.title == "Dinner")
        #expect(draft.total == usd(3000))
        #expect(draft.date == nil)
    }
}
