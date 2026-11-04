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
}
