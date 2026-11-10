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

    @Test func movingToAnotherGroupKeepsTheChosenCurrencyAndTheItems() throws {
        let harness = try ExpenseFormHarness()
        let trip = SplitGroup(name: "Trip", currencyCode: "USD", memberIDs: [harness.me, harness.priya])
        try harness.fixture.services.groups.create(trip)
        let model = harness.newExpense()
        model.changeCurrency(to: "EUR")
        var parsed = ParsedReceipt(currencyCode: "EUR")
        func euros(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "EUR") }
        parsed.items = [
            ReceiptLineItem(name: "Pasta", quantity: 1, unitPrice: nil, total: euros(1800)),
            ReceiptLineItem(name: "Wine", quantity: 1, unitPrice: nil, total: euros(900))
        ]
        parsed.tax = euros(200)
        parsed.tip = euros(300)
        parsed.total = euros(3200)
        model.apply(receipt: parsed)
        model.assign(harness.sam, to: model.split.items[0].id)

        model.switchGroup(to: trip.id)
        #expect(model.group?.id == trip.id)
        #expect(model.currencyCode == "EUR")
        #expect(model.total == euros(3200))
        #expect(model.split.method == .itemized)
        #expect(model.split.items.map(\.name) == ["Pasta", "Wine"])
        #expect(model.split.items.map(\.amountText) == ["18.00", "9.00"])
        #expect(model.split.items.allSatisfy { $0.assignees.isEmpty })
        #expect(model.split.taxText == "2.00")
        #expect(model.split.tipText == "3.00")
        #expect(model.participants == [harness.me, harness.priya])
    }

    @Test func movingToAnotherGroupTakesItsCurrencyAndAnEqualSplit() throws {
        let harness = try ExpenseFormHarness()
        let trip = SplitGroup(name: "Trip", currencyCode: "EUR", memberIDs: [harness.me, harness.priya])
        try harness.fixture.services.groups.create(trip)
        let model = harness.filledDinner()
        model.selectMethod(.exact)
        #expect(model.split.exact[harness.sam] == "20.00")

        model.switchGroup(to: trip.id)
        #expect(model.currencyCode == "EUR")
        #expect(model.split.method == .equal)
        #expect(model.split.exact.isEmpty)
        #expect(model.issue == nil)
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

    @Test func aDuplicateLeavesOutSomeoneWhoLeftTheGroup() throws {
        let harness = try ExpenseFormHarness()
        let gone = Person(name: "Maya", avatarSeed: 3)
        try harness.fixture.services.people.add(gone)
        let old = Expense(
            groupID: harness.fixture.group.id, title: "Dinner", total: usd(9000), date: Date(), paidBy: harness.me,
            split: .equal(participants: [harness.me, harness.sam, gone.id])
        )
        let model = harness.newExpense(prefill: ExpenseDraft(copying: old))
        #expect(model.participants == [harness.me, harness.sam])
        let saved = try model.save()
        #expect(try saved.shares().shares == [harness.me: usd(4500), harness.sam: usd(4500)])
    }

    @Test func aDuplicateDropsThePaymentsAndItemsOfSomeoneWhoLeft() throws {
        let harness = try ExpenseFormHarness()
        let gone = Person(name: "Maya", avatarSeed: 3)
        try harness.fixture.services.people.add(gone)
        let items = ItemizedSplit(items: [
            SplitItem(name: "Pasta", amount: usd(6000), assignees: [harness.me, gone.id]),
            SplitItem(name: "Wine", amount: usd(3000), assignees: [harness.sam])
        ])
        let old = Expense(
            groupID: harness.fixture.group.id, title: "Dinner", total: usd(9000), date: Date(),
            payers: [harness.me: usd(4000), gone.id: usd(5000)], split: .itemized(items)
        )
        let model = harness.newExpense(prefill: ExpenseDraft(copying: old))
        #expect(!model.payer.isMultiple)
        #expect(model.payer.single == harness.me)
        #expect(model.split.items.map(\.assignees) == [[harness.me], [harness.sam]])
        let saved = try model.save()
        #expect(saved.payers == [harness.me: usd(9000)])
        #expect(try saved.shares().shares == [harness.me: usd(6000), harness.sam: usd(3000)])
    }

    @Test func aDuplicateForgetsWhatSomeoneWhoLeftOwedExactly() throws {
        let harness = try ExpenseFormHarness()
        let gone = Person(name: "Maya", avatarSeed: 3)
        try harness.fixture.services.people.add(gone)
        let old = Expense(
            groupID: harness.fixture.group.id, title: "Dinner", total: usd(9000), date: Date(), paidBy: harness.me,
            split: .exact(amounts: [harness.me: usd(4000), gone.id: usd(5000)])
        )
        let model = harness.newExpense(prefill: ExpenseDraft(copying: old))
        #expect(model.participants == [harness.me])
        #expect(model.split.exact == [harness.me: "40.00"])
        // The rest is shown as still to assign, not kept for someone the form cannot show.
        #expect(model.issue == .splitShort(usd(5000)))
    }

    @Test func aRefundStaysARefundWhenItsAmountIsRetyped() throws {
        let harness = try ExpenseFormHarness()
        let refund = Expense(
            groupID: harness.fixture.group.id, title: "Refund", total: usd(-3000), date: Date(), paidBy: harness.me,
            split: .equal(participants: harness.fixture.everyone)
        )
        try harness.fixture.services.expenses.add(refund)
        let model = harness.editor(for: refund.id)
        #expect(model.total == usd(-3000))
        #expect(model.signedAmountText == "-30.00")
        #expect(!model.isDirty)

        // The number pad has no minus key, so clearing the amount leaves only digits to type.
        model.amountText = ""
        #expect(model.signedAmountText == "")
        model.amountText = "25"
        #expect(model.signedAmountText == "-25")
        #expect(model.total == usd(-2500))
        #expect(try model.save().total == usd(-2500))
        #expect(try harness.fixture.services.expenses.expense(id: refund.id)?.total == usd(-2500))
    }

    @Test func aRecurringRefundOpensReadyToSave() throws {
        let harness = try ExpenseFormHarness()
        let fixture = harness.fixture
        let template = RecurringExpense(
            groupID: fixture.group.id, title: "Cashback", total: usd(-3000), payers: [harness.me: usd(-3000)],
            split: .equal(participants: fixture.everyone), rule: RecurrenceRule(frequency: .monthly, startDate: fixture.clock.start)
        )
        try fixture.services.recurring.add(template)
        let editor = ExpenseFormModel(mode: .editRecurring(template), services: fixture.services, dependencies: harness.dependencies)
        #expect(editor.total == usd(-3000))
        #expect(editor.issue == nil)

        editor.amountText = "35"
        try editor.save()
        let updated = try #require(try fixture.services.recurring.templates(in: fixture.group.id).first)
        #expect(updated.total == usd(-3500))
    }

    @Test func aNewExpenseDoesNotBecomeARefund() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        #expect(!model.isRefund)
        #expect(model.signedAmountText == "60")
        model.amountText = "-25"
        #expect(model.total == nil)
        #expect(!model.canSave)
    }

    @Test func chipsSayYouForThePersonUsingTheApp() throws {
        let harness = try ExpenseFormHarness()
        #expect(PeopleChips.name(of: harness.fixture.me, currentPerson: harness.me) == "You")
        #expect(PeopleChips.name(of: harness.fixture.sam, currentPerson: harness.me) == "Sam")
        #expect(PeopleChips.name(of: harness.fixture.me, currentPerson: nil) == "Me")
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

    @Test func aPastedPageIsCutToTheLengthOfANote() async throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.describeText = "Dinner 60 " + String(repeating: "Sam owes 5 ", count: 20_000)
        await model.fillFromNote()
        #expect(model.amountText == "60.00")
    }

    @Test func aGroupBeingLeftIsNotOffered() throws {
        let harness = try ExpenseFormHarness()
        let trip = SplitGroup(name: "Trip", currencyCode: "EUR", memberIDs: [harness.me, harness.sam])
        try harness.fixture.services.groups.create(trip)
        let model = harness.newExpense()
        #expect(model.availableGroups.count == 2)
        LeftGroupsStore(defaults: harness.defaults).insert(trip.id)
        #expect(model.availableGroups.map(\.id) == [harness.fixture.group.id])
    }

    @Test func aLineBreakInATitleIsNotStored() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.title = "Dinner\nat Sam's\n"
        #expect(try model.save().title == "Dinner at Sam's")
    }
}
