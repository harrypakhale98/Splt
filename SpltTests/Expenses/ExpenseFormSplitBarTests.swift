import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Expense form split bar")
@MainActor
struct ExpenseFormSplitBarTests {
    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    @Test func theBarShowsEveryoneInTheSplit() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        let data = try #require(model.barData)
        #expect(data.segments.count == 3)
        #expect(data.scale == SplitBarMath.basisPoints)
        #expect(data.canDrag)
        #expect(data.segments.compactMap(\.amount).map(\.minorUnits).reduce(0, +) == 6000)
        #expect(data.weights.reduce(0, +) == 10_000)
    }

    @Test func noAmountMeansNoDragging() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        let data = try #require(model.barData)
        #expect(!data.canDrag)
        #expect(model.dragDivider(0, toFraction: 0.5) == nil)
    }

    @Test func nobodyInTheSplitMeansNoBar() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.participants = []
        #expect(model.barData == nil)
        #expect(model.summaryLine.contains("split 0 ways"))
    }

    @Test func draggingAnEqualBarSwitchesToPercentages() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        let result = try #require(model.dragDivider(0, toFraction: 0.5))
        #expect(model.split.method == .percentage)
        #expect(result.didChange)
        #expect(model.percentRemaining == 0)
        #expect(model.issue == nil)
        #expect(model.barData?.weights.reduce(0, +) == 10_000)
    }

    @Test func dividersClickIntoTheEqualSplit() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.dragDivider(0, toFraction: 0.5)
        let back = try #require(model.dragDivider(0, toFraction: 0.34))
        #expect(back.snappedTo == .equal)
        let amounts = model.sharePreview.map(\.amount.minorUnits)
        #expect(amounts.reduce(0, +) == 6000)
        #expect(Set(amounts).count <= 2)
    }

    @Test func percentDragsStayTidy() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.selectMethod(.percentage)
        model.dragDivider(0, toFraction: 0.4212, thresholdBasisPoints: 10)
        let first = try #require(AmountInput.basisPoints(model.split.percent[model.barPeople[0].id, default: ""], locale: model.locale))
        #expect(first % 100 == 0)
    }

    @Test func exactDragsMoveWholeDollarsAndKeepTheTotal() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.selectMethod(.exact)
        #expect(model.issue == nil)
        model.dragDivider(0, toFraction: 0.5, thresholdBasisPoints: 10)
        #expect(model.split.method == .exact)
        #expect(model.splitRemaining == usd(0))
        #expect(model.issue == nil)
        let first = try #require(model.barData?.segments.first?.amount?.minorUnits)
        #expect(first % 100 == 0)
    }

    @Test func sharesDragsStayWholeNumbers() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.selectMethod(.shares)
        model.dragDivider(0, toFraction: 0.6)
        let counts = model.barPeople.map { model.shareCount(for: $0.id) }
        #expect(counts.allSatisfy { $0 >= 1 && $0.rounded() == $0 })
        #expect(counts[0] > counts[1])
        #expect(model.issue == nil)
    }

    @Test func adjustDragsKeepAnEqualBaseAndTheTotal() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.selectMethod(.adjustment)
        model.dragDivider(0, toFraction: 0.5, thresholdBasisPoints: 10)
        #expect(model.issue == nil)
        let total = model.sharePreview.map(\.amount.minorUnits).reduce(0, +)
        #expect(total == 6000)
        let first = try #require(model.sharePreview.first?.amount.minorUnits)
        #expect(first > 2000)
    }

    @Test func switchingMethodsCarriesTheSplitOver() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.selectMethod(.percentage)
        model.dragDivider(0, toFraction: 0.5, thresholdBasisPoints: 10)
        let percentAmounts = model.sharePreview.map(\.amount.minorUnits)

        model.selectMethod(.exact)
        #expect(model.sharePreview.map(\.amount.minorUnits) == percentAmounts)
        #expect(model.issue == nil)

        model.selectMethod(.equal)
        #expect(model.split.method == .equal)
        #expect(Set(model.sharePreview.map(\.amount.minorUnits)).count == 1)
    }

    @Test func switchingToAdjustmentsKeepsAnEqualSplitEqualToTheCent() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.amountText = "120.01"
        model.title = "Odd"
        let before = model.sharePreview.map { $0.amount.minorUnits }
        model.selectMethod(.adjustment)
        #expect(model.split.adjustments.values.allSatisfy { $0.isEmpty })
        #expect(model.sharePreview.map { $0.amount.minorUnits } == before)

        model.selectMethod(.exact)
        #expect(model.sharePreview.map { $0.amount.minorUnits } == before)
        #expect(model.issue == nil)
    }

    @Test func switchingFromEqualToSharesStartsAtOneEach() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.selectMethod(.shares)
        #expect(model.barPeople.allSatisfy { model.shareCount(for: $0.id) == 1 })
    }

    @Test func stepsChangeOneUnitAtATime() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        let me = harness.me
        #expect(model.adjustShare(of: me, increase: true))
        #expect(model.split.method == .percentage)
        let before = try #require(model.barData?.segments.first { $0.id == me }?.weight)
        #expect(model.adjustShare(of: me, increase: true))
        let after = try #require(model.barData?.segments.first { $0.id == me }?.weight)
        #expect(after - before == 100)
        #expect(model.percentRemaining == 0)
    }

    @Test func shareStepsNeverGoBelowOne() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.selectMethod(.shares)
        #expect(!model.adjustShare(of: harness.me, increase: false))
        #expect(model.adjustShare(of: harness.me, increase: true))
        #expect(model.shareCount(for: harness.me) == 2)
    }

    @Test func itemsDoNotDrag() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.split.method = .itemized
        model.split.items = [ItemDraft(name: "Pasta", amountText: "60", assignees: [harness.me, harness.sam])]
        let data = try #require(model.barData)
        #expect(!data.canDrag)
        #expect(data.segments.count == 2)
        #expect(model.dragDivider(0, toFraction: 0.5) == nil)
    }

    @Test func tappingPeopleIncludesThemOrAssignsTheSelectedItem() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.tapPerson(harness.sam)
        #expect(!model.participants.contains(harness.sam))

        model.split.method = .itemized
        model.split.items = [ItemDraft(name: "Pasta", amountText: "60", assignees: [])]
        model.selectedItemID = model.split.items[0].id
        model.tapPerson(harness.priya)
        #expect(model.split.items[0].assignees == [harness.priya])
        #expect(!model.participants.contains(harness.sam))
    }

    @Test func holdingAPersonSetsWhoPaid() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.makeSolePayer(harness.sam)
        #expect(model.isPayer(harness.sam))
        #expect(!model.isPayer(harness.me))
        #expect(model.summaryLine.hasPrefix("Sam paid"))
    }

    @Test func severalPayersShareTheAmountAndFollowIt() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.toggleAlsoPaid(harness.sam)
        #expect(model.payer.isMultiple)
        #expect(model.isPayer(harness.me) && model.isPayer(harness.sam))
        #expect(model.payerRemaining == usd(0))
        #expect(model.issue == nil)

        model.amountText = "80"
        model.refollowPayments()
        #expect(model.payerRemaining == usd(0))

        model.toggleAlsoPaid(harness.sam)
        #expect(!model.payer.isMultiple)
        #expect(model.payer.single == harness.me)
    }

    @Test func theSummaryNamesWhoPaidAndHowItSplits() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        let us = model.locale
        let amount = MoneyFormatting.magnitudeString(usd(6000), locale: us)
        #expect(model.summaryLine == "You paid \(amount), split 3 ways")
        model.selectMethod(.percentage)
        #expect(model.summaryLine.hasSuffix("split by percent"))
        model.toggleAlsoPaid(harness.sam)
        #expect(model.summaryLine.hasPrefix("2 people paid"))
        model.amountText = ""
        #expect(model.summaryLine == "Enter an amount to get started.")
    }

    @Test func aScanSelectsTheFirstItemForAssignment() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        var receipt = ParsedReceipt(currencyCode: "USD")
        receipt.items = [ReceiptLineItem(name: "Soup", quantity: 1, unitPrice: nil, total: usd(900))]
        receipt.total = usd(900)
        model.apply(receipt: receipt)
        #expect(model.selectedItemID == model.split.items.first?.id)
    }

    @Test func detailBarsShowReadOnlyShares() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Dinner", cents: 3000)
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: Locale(identifier: "en_US"))
        let data = try #require(model.splitBarData)
        #expect(!data.canDrag)
        #expect(data.segments.count == 3)
        #expect(data.weights.reduce(0, +) == 3000)
        #expect(model.memberIDs.count == 3)
    }
}
