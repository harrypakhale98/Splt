import Foundation
import SpltCore
import Testing
import UIKit
@testable import Splt

@Suite("Expense form saving")
@MainActor
struct ExpenseFormSavingTests {
    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    private func jpeg() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60))
        return renderer.jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
    }

    @Test func savingAddsTheExpenseWithTheChosenSplit() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.category = .dining
        model.note = " Birthday "
        let saved = try model.save()

        let stored = try #require(try harness.fixture.services.expenses.expense(id: saved.id))
        #expect(stored.title == "Dinner")
        #expect(stored.total == usd(6000))
        #expect(stored.category == .dining)
        #expect(stored.note == "Birthday")
        #expect(stored.payers == [harness.me: usd(6000)])
        #expect(stored.split == .equal(participants: harness.fixture.everyone))
        #expect(model.saveCount == 1)
        #expect(harness.defaults.string(forKey: ExpenseFormModel.lastGroupKey) == harness.fixture.group.id.description)
    }

    @Test func savingBlockedFormsThrows() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        #expect(throws: ExpenseFormModel.SaveFailure.self) { try model.save() }
        #expect(model.saveCount == 0)
    }

    @Test func exactSplitIsStoredAsTyped() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.split.method = .exact
        model.split.exact = [harness.me: "30", harness.sam: "20", harness.priya: "10"]
        let saved = try model.save()
        #expect(saved.split == .exact(amounts: [harness.me: usd(3000), harness.sam: usd(2000), harness.priya: usd(1000)]))
    }

    @Test func severalPayersAreStored() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.setMultiplePayers(true)
        model.togglePayer(harness.sam)
        model.payer.amounts = [harness.me: "35", harness.sam: "25"]
        let saved = try model.save()
        #expect(saved.payers == [harness.me: usd(3500), harness.sam: usd(2500)])
    }

    @Test func editingLoadsAndKeepsAnUnchangedExpenseUntouched() throws {
        let harness = try ExpenseFormHarness()
        let created = try harness.fixture.addExpense("Taxi", cents: 2500, paidBy: harness.fixture.sam)
        let model = harness.editor(for: created.id)
        #expect(model.title == "Taxi")
        #expect(model.amountText == "25.00")
        #expect(model.payer.single == harness.sam)
        #expect(!model.isDirty)

        try model.save()
        let history = try harness.fixture.services.expenses.details(id: created.id)?.history
        #expect(history?.isEmpty == true)
    }

    @Test func editingRecordsWhatChanged() throws {
        let harness = try ExpenseFormHarness()
        let created = try harness.fixture.addExpense("Taxi", cents: 2500)
        let model = harness.editor(for: created.id)
        model.title = "Airport taxi"
        #expect(model.isDirty)
        try model.save()

        let stored = try #require(try harness.fixture.services.expenses.expense(id: created.id))
        #expect(stored.title == "Airport taxi")
        let history = try #require(try harness.fixture.services.expenses.details(id: created.id)?.history)
        #expect(history.count == 1)
        #expect(history[0].changedFields == [.title])
        #expect(history[0].previousTitle == "Taxi")
    }

    @Test func editingKeepsAnItemizedSplitIntact() throws {
        let harness = try ExpenseFormHarness()
        let split = SplitDefinition.itemized(ItemizedSplit(
            items: [
                SplitItem(name: "Pizza", amount: usd(2000), assignees: [harness.me, harness.sam]),
                SplitItem(name: "Beer", amount: usd(1000), assignees: [harness.priya])
            ],
            tip: usd(300)
        ))
        let created = Expense(
            groupID: harness.fixture.group.id, title: "Pizza night", total: usd(3300),
            date: harness.fixture.clock.start, paidBy: harness.me, split: split
        )
        try harness.fixture.services.expenses.add(created)

        let model = harness.editor(for: created.id)
        #expect(model.split.method == .itemized)
        #expect(model.issue == nil)
        try model.save()
        #expect(try harness.fixture.services.expenses.details(id: created.id)?.history.isEmpty == true)
    }

    @Test func receiptPhotosAreStoredAsFilesNotInTheDatabase() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.receipt.pendingImage = jpeg()
        let saved = try model.save()

        let extras = try #require(try harness.fixture.services.expenses.details(id: saved.id)?.extras)
        let name = try #require(extras.receiptFileName)
        #expect(harness.receipts.exists(name))
        #expect(harness.receipts.thumbnail(named: name) != nil)

        let editor = harness.editor(for: saved.id)
        editor.clearReceipt()
        try editor.save()
        #expect(!harness.receipts.exists(name))
        #expect(try harness.fixture.services.expenses.details(id: saved.id)?.extras.receiptFileName == nil)
    }

    @Test func aRepeatingExpenseCreatesItsTemplateAndFirstOccurrence() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.title = "Rent"
        model.amountText = "900"
        model.repeatChoice.frequency = .monthly
        let saved = try model.save()

        let templates = try harness.fixture.services.recurring.templates(in: harness.fixture.group.id)
        let template = try #require(templates.first)
        #expect(templates.count == 1)
        #expect(template.total == usd(90_000))
        #expect(template.lastCreatedOccurrence == saved.date)
        #expect(saved.id == OccurrenceID.expenseID(template: template.id, occurrence: saved.date))
        let extras = try harness.fixture.services.expenses.details(id: saved.id)?.extras
        #expect(extras?.recurringExpenseID == template.id)

        let month: TimeInterval = 40 * 86_400
        let later = saved.date.addingTimeInterval(month)
        let created = RecurringExpenseGenerator.run(services: harness.fixture.services, now: later)
        #expect(created.count == 1)
        let again = RecurringExpenseGenerator.run(services: harness.fixture.services, now: later)
        #expect(again.isEmpty)
        #expect(try harness.fixture.services.expenses.expenses(in: harness.fixture.group.id).count == 2)
    }

    @Test func editingATemplateUpdatesIt() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.title = "Gym"
        model.amountText = "30"
        model.repeatChoice.frequency = .monthly
        try model.save()
        let template = try #require(try harness.fixture.services.recurring.templates(in: harness.fixture.group.id).first)

        let editor = ExpenseFormModel(mode: .editRecurring(template), services: harness.fixture.services, dependencies: harness.dependencies)
        #expect(editor.isEditingRecurring)
        #expect(editor.title == "Gym")
        editor.amountText = "35"
        editor.repeatChoice.frequency = .weekly
        try editor.save()

        let updated = try #require(try harness.fixture.services.recurring.templates(in: harness.fixture.group.id).first)
        #expect(updated.total == usd(3500))
        #expect(updated.rule.frequency == .weekly)
        #expect(updated.lastCreatedOccurrence == template.lastCreatedOccurrence)
    }

    @Test func aRecurringTemplateOffersNoReceipt() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.title = "Gym"
        model.amountText = "30"
        model.repeatChoice.frequency = .monthly
        #expect(model.canAttachReceipt)
        let saved = try model.save()
        #expect(harness.editor(for: saved.id).canAttachReceipt)

        let template = try #require(try harness.fixture.services.recurring.templates(in: harness.fixture.group.id).first)
        let editor = ExpenseFormModel(mode: .editRecurring(template), services: harness.fixture.services, dependencies: harness.dependencies)
        #expect(!editor.canAttachReceipt)
    }

    @Test func duplicatesAreFoundBeforeSaving() throws {
        let harness = try ExpenseFormHarness()
        try harness.fixture.addExpense("Dinner", cents: 6000)
        let model = harness.filledDinner()
        model.refreshDuplicates()
        #expect(model.possibleDuplicates.count == 1)

        model.amountText = "61"
        model.refreshDuplicates()
        #expect(model.possibleDuplicates.isEmpty)
    }

    @Test func duplicateDraftCopiesTheExpenseWithATodayDate() throws {
        let harness = try ExpenseFormHarness()
        let original = try harness.fixture.addExpense("Dinner", cents: 6000, paidBy: harness.fixture.sam)
        let model = harness.newExpense(prefill: ExpenseDraft(copying: original))
        #expect(model.title == "Dinner")
        #expect(model.amountText == "60.00")
        #expect(model.payer.single == harness.sam)
        #expect(model.date == harness.fixture.clock.start)
        #expect(model.canSave)
    }
}
