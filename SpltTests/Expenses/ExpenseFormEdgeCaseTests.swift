import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Expense form edge cases")
@MainActor
struct ExpenseFormEdgeCaseTests {
    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    private func item(_ name: String, _ cents: Int64) -> ReceiptLineItem {
        ReceiptLineItem(name: name, quantity: 1, unitPrice: nil, total: usd(cents))
    }

    @Test func aNoteWithOnlyAShareKeepsItsCurrency() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.describeText = "Sam owes €20"
        await model.fillFromNote()
        #expect(model.currencyCode == "EUR")
        #expect(model.split.exact[harness.sam] == "20.00")
    }

    @Test func onlyUnknownNamesGiveNoEmptyNotice() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        var draft = QuickAddDraft()
        draft.participantNames = ["Zed"]
        model.apply(quickAdd: draft)
        #expect(model.filledNotice == nil)
        #expect(model.unmatchedNames == ["Zed"])
    }

    @Test func aSharedFirstNameIsNotReportedAsMissing() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.members = [harness.fixture.me, Person(name: "Sam Lee", avatarSeed: 7), Person(name: "Sam Roy", avatarSeed: 8)]
        var draft = QuickAddDraft()
        draft.title = "Dinner"
        draft.participantNames = ["Sam", "Zed"]
        model.apply(quickAdd: draft)
        #expect(model.ambiguousNames == ["Sam"])
        #expect(model.unmatchedNames == ["Zed"])
    }

    @Test func changingOnlyTheDateIsAnUnsavedChange() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        #expect(!model.isDirty)
        model.date = model.date.addingTimeInterval(-3 * 86_400)
        #expect(model.isDirty)
    }

    @Test func aSecondSaveStoresNothing() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        let first = try model.save()
        let second = try model.save()
        #expect(first.id == second.id)
        #expect(model.saveCount == 1)
        #expect(try harness.fixture.services.expenses.expenses(in: harness.fixture.group.id).count == 1)
    }

    @Test func aSecondSaveOfARepeatingExpenseStoresNothing() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.repeatChoice.frequency = .monthly
        try model.save()
        try model.save()
        #expect(try harness.fixture.services.recurring.templates(in: harness.fixture.group.id).count == 1)
    }

    @Test func aFailedSaveCanBeTriedAgain() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        #expect(throws: ExpenseFormModel.SaveFailure.self) { try model.save() }
        model.amountText = "60"
        model.title = "Dinner"
        #expect(try model.save().title == "Dinner")
    }
}
