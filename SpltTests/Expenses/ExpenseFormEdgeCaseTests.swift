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

    @Test func decimalsAYenAmountCannotHaveAreExplained() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.amountText = "12.50"
        model.changeCurrency(to: "JPY")
        #expect(model.issue == .invalidAmount)
        model.amountText = "1250"
        #expect(model.issue == nil)
        model.amountText = ""
        #expect(model.issue == .missingAmount)
    }

    @Test func aCouponLineBecomesTheDiscount() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        var parsed = ParsedReceipt(currencyCode: "USD")
        parsed.items = [item("Pasta", 2000), item("Coupon", -200)]
        parsed.subtotal = usd(1800)
        parsed.total = usd(1800)
        model.apply(receipt: parsed)
        #expect(model.split.items.map(\.name) == ["Pasta"])
        #expect(model.split.discountText == "2.00")
        #expect(model.amountText == "18.00")
        model.title = "Cafe"
        for item in model.split.items { model.assignEveryone(to: item.id) }
        #expect(model.issue == nil)
    }

    @Test func aReceiptWithOnlyNegativeLinesHasNoItems() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        var parsed = ParsedReceipt(currencyCode: "USD")
        parsed.items = [item("Refund", -200)]
        model.apply(receipt: parsed)
        #expect(model.split.items.isEmpty)
        #expect(model.split.method == .equal)
        #expect(model.scanNotice != nil)
    }

    @Test func onlyRealGroupsAreOfferedWhenMoving() throws {
        let harness = try ExpenseFormHarness()
        let direct = SplitGroup(name: "Direct", currencyCode: "USD", kind: .friend, memberIDs: [harness.me, harness.sam])
        try harness.fixture.services.groups.create(direct)
        let model = harness.newExpense()
        #expect(model.availableGroups.map(\.id) == [harness.fixture.group.id])
    }

    @Test func aDuplicatedRefundKeepsItsTotal() throws {
        let harness = try ExpenseFormHarness()
        let refund = Expense(
            groupID: harness.fixture.group.id, title: "Refund", total: usd(-3000), date: Date(), paidBy: harness.me,
            split: .equal(participants: harness.fixture.everyone)
        )
        let model = harness.newExpense(prefill: ExpenseDraft(copying: refund))
        #expect(model.total == usd(-3000))
        #expect(model.issue == nil)
    }

    @Test func negativeAmountsDisplayWithoutAStrayGroupMark() {
        let english = Locale(identifier: "en_US")
        #expect(AmountKeypad.display("-123.00", locale: english) == "-123.00")
        #expect(AmountKeypad.display("-1234.00", locale: english) == "-1,234.00")
        #expect(AmountKeypad.display("1234", locale: english) == "1,234")
    }

    @Test func oneScannedItemReadsAsSingular() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        var parsed = ParsedReceipt(currencyCode: "USD")
        parsed.items = [item("Pasta", 2000)]
        parsed.total = usd(2000)
        model.apply(receipt: parsed)
        #expect(model.scanNotice?.hasPrefix("Scanned 1 item.") == true)
    }

    @Test func oneWayReadsAsSingular() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.participants = [harness.me]
        #expect(model.summaryLine.hasSuffix("split 1 way"))
    }

    @Test func aRefundWithExactAmountsHasNothingLeftToAssign() throws {
        let harness = try ExpenseFormHarness()
        let refund = Expense(
            groupID: harness.fixture.group.id, title: "Refund", total: usd(-3000), date: Date(), paidBy: harness.me,
            split: .exact(amounts: [harness.me: usd(-1000), harness.sam: usd(-2000)])
        )
        try harness.fixture.services.expenses.add(refund)
        let model = harness.editor(for: refund.id)
        #expect(model.splitRemaining?.isZero == true)
        #expect(model.issue == nil)
    }
}
