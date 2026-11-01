import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Expense form smart entry")
@MainActor
struct ExpenseFormSmartEntryTests {
    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    @Test func aNoteFillsTheForm() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.describeText = "Taxi 30 with Sam, I paid"
        await model.fillFromNote()

        #expect(model.amountText == "30.00")
        #expect(model.title.localizedCaseInsensitiveContains("taxi"))
        #expect(model.participants == [harness.me, harness.sam])
        #expect(model.payer.single == harness.me)
        #expect(model.filledNotice != nil)
        #expect(model.canSave)
    }

    @Test func aNamedPayerIsChosen() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.describeText = "Dinner 90 with Sam and Priya, Sam paid"
        await model.fillFromNote()
        #expect(model.payer.single == harness.sam)
        #expect(model.participants == harness.fixture.everyone)
    }

    @Test func peopleOutsideTheGroupAreReported() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        var draft = QuickAddDraft()
        draft.title = "Pizza"
        draft.amount = usd(2400)
        draft.participantNames = ["Sam", "Zed"]
        model.apply(quickAdd: draft)
        #expect(model.unmatchedNames == ["Zed"])
        #expect(model.participants == [harness.me, harness.sam])
    }

    @Test func exactAmountsFromANoteShareTheRestEqually() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        var draft = QuickAddDraft()
        draft.title = "Dinner"
        draft.amount = usd(9000)
        draft.participantNames = ["Sam", "Priya"]
        draft.splitHint = .exactAmounts([QuickAddShare(name: "Priya", amount: usd(2000))])
        model.apply(quickAdd: draft)

        #expect(model.split.method == .exact)
        #expect(model.issue == nil)
        let byPerson = Dictionary(uniqueKeysWithValues: model.sharePreview.map { ($0.person.id, $0.amount) })
        #expect(byPerson[harness.priya] == usd(2000))
        #expect(byPerson[harness.me] == usd(3500))
        #expect(byPerson[harness.sam] == usd(3500))
    }

    @Test func adjustmentsFromANoteAreApplied() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        var draft = QuickAddDraft()
        draft.title = "Dinner"
        draft.amount = usd(6000)
        draft.splitHint = .adjustments([QuickAddShare(name: "Priya", amount: usd(-1000))])
        model.apply(quickAdd: draft)
        #expect(model.split.method == .adjustment)
        #expect(model.split.adjustments[harness.priya] == "-10.00")
        #expect(model.issue == nil)
    }

    @Test func anEmptyNoteChangesNothing() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.apply(quickAdd: QuickAddDraft())
        #expect(model.amountText.isEmpty)
        #expect(model.filledNotice != nil)
    }

    @Test func suggestedCategoriesAreOffersNotChanges() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.title = "Uber to the airport"
        model.titleDidChange()
        try await Task.sleep(for: .milliseconds(900))
        #expect(model.category == .general)
        let suggestion = try #require(model.suggestedCategory)
        model.acceptSuggestedCategory()
        #expect(model.category == suggestion)
        #expect(model.suggestedCategory == nil)
    }

    @Test func categoryHintsMapOntoAppCategories() {
        #expect(ExpenseCategory(.food) == .dining)
        #expect(ExpenseCategory(.lodging) == .lodging)
        #expect(ExpenseCategory(.other) == .other)
        #expect(Set(ExpenseCategoryHint.allCases.map { ExpenseCategory($0) }).count >= 10)
    }

    @Test func aScannedReceiptOpensTheItemizedEditor() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        var receipt = ParsedReceipt(currencyCode: "USD")
        receipt.merchant = "Corner Cafe"
        receipt.items = [
            ReceiptLineItem(name: "Pasta", quantity: 1, unitPrice: nil, total: usd(1200)),
            ReceiptLineItem(name: "Wine", quantity: 1, unitPrice: nil, total: usd(800))
        ]
        receipt.tax = usd(200)
        receipt.tip = usd(300)
        receipt.total = usd(2500)
        model.apply(receipt: receipt)

        #expect(model.split.method == .itemized)
        #expect(model.title == "Corner Cafe")
        #expect(model.amountText == "25.00")
        #expect(model.split.items.count == 2)
        #expect(model.split.taxText == "2.00")
        #expect(model.issue == .itemWithoutPeople(name: "Pasta"))

        for item in model.split.items { model.assignEveryone(to: item.id) }
        #expect(model.issue == nil)
    }

    @Test func extraChargesBecomeTaxOrDiscount() throws {
        let harness = try ExpenseFormHarness()
        let fee = harness.newExpense()
        var receipt = ParsedReceipt(currencyCode: "USD")
        receipt.items = [ReceiptLineItem(name: "Soup", quantity: 1, unitPrice: nil, total: usd(1000))]
        receipt.otherCharges = usd(150)
        receipt.total = usd(1150)
        fee.apply(receipt: receipt)
        #expect(fee.split.taxText == "1.50")

        let discount = harness.newExpense()
        receipt.otherCharges = usd(-200)
        receipt.total = usd(800)
        discount.apply(receipt: receipt)
        #expect(discount.split.discountText == "2.00")
        #expect(discount.split.taxText.isEmpty)
    }

    @Test func aReceiptWithNoItemsOnlyAddsANotice() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.apply(receipt: ParsedReceipt(currencyCode: "USD"))
        #expect(model.split.method == .equal)
        #expect(model.scanNotice != nil)
    }

    @Test func otherCurrenciesShowTheGroupValue() throws {
        let harness = try ExpenseFormHarness()
        var group = harness.fixture.group
        group.pinnedRate = PinnedRate(from: "EUR", to: "USD", rate: Decimal(string: "1.1")!)
        try harness.fixture.services.groups.update(group)

        let model = harness.newExpense()
        #expect(model.convertedTotal == nil)
        model.changeCurrency(to: "eur")
        model.amountText = "100"
        #expect(model.currencyCode == "EUR")
        #expect(model.convertedTotal == usd(11_000))
        #expect(model.rateText != nil)
        #expect(!model.lacksRate)

        model.changeCurrency(to: "GBP")
        #expect(model.convertedTotal == nil)
        #expect(model.lacksRate)
    }
}
