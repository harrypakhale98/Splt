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

    @Test func paymentsTypedByHandStayWhenTheAmountChanges() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.amountText = "100"
        model.toggleAlsoPaid(harness.sam)
        model.setPayerAmount("70", for: harness.me)
        model.setPayerAmount("30", for: harness.sam)
        #expect(model.issue == nil)

        model.amountText = "120"
        model.refollowPayments()
        #expect(model.payer.amounts[harness.me] == "70")
        #expect(model.payer.amounts[harness.sam] == "30")
        #expect(model.issue == .payersShort(usd(2000)))
    }

    @Test func choosingPayersByHandStopsFollowingTheAmount() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.toggleAlsoPaid(harness.sam)
        model.togglePayer(harness.priya)
        model.amountText = "90"
        model.refollowPayments()
        #expect(model.payer.amounts[harness.priya] == nil)
        #expect(model.payer.amounts[harness.me] == "30.00")

        let other = harness.filledDinner()
        other.toggleAlsoPaid(harness.sam)
        other.setMultiplePayers(true)
        other.amountText = "90"
        other.refollowPayments()
        #expect(other.payer.amounts[harness.me] == "30.00")
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

    // MARK: The bar says what the expense really charges

    /// The bar's amounts are the calculator's shares, and they add up to the total.
    private func expectBarShowsRealShares(_ model: ExpenseFormModel, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let data = try #require(model.barData, sourceLocation: sourceLocation)
        let real = Dictionary(uniqueKeysWithValues: model.sharePreview.map { ($0.person.id, $0.amount) })
        #expect(real.count == data.segments.count, sourceLocation: sourceLocation)
        for segment in data.segments {
            #expect(segment.amount == real[segment.id], sourceLocation: sourceLocation)
        }
        #expect(data.segments.compactMap(\.amount).map(\.minorUnits).reduce(0, +) == model.total?.minorUnits, sourceLocation: sourceLocation)
        #expect(model.issue == nil, sourceLocation: sourceLocation)
    }

    private func share(of person: PersonID, in model: ExpenseFormModel) -> Int64? {
        model.sharePreview.first { $0.person.id == person }?.amount.minorUnits
    }

    @Test func anEqualBarShowsTheRealShares() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.amountText = "300"
        let data = try #require(model.barData)
        #expect(data.segments.map(\.amount) == [usd(10_000), usd(10_000), usd(10_000)])
        model.amountText = "1000"
        try expectBarShowsRealShares(model)
    }

    @Test func anAdjustBarWithNoAdjustmentsSaysEven() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.amountText = "1000"
        model.selectMethod(.adjustment)
        let data = try #require(model.barData)
        for segment in data.segments { #expect(segment.adjustment?.isZero == true) }
        try expectBarShowsRealShares(model)
    }

    @Test func anExactBarKeepsTheTypedCents() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.amountText = "1234.56"
        model.selectMethod(.exact)
        model.split.exact = [harness.me: "100.01", harness.sam: "200.02", harness.priya: "934.53"]
        let data = try #require(model.barData)
        let byPerson = Dictionary(uniqueKeysWithValues: data.segments.map { ($0.id, $0.amount?.minorUnits) })
        #expect(byPerson[harness.me] == 10001)
        #expect(byPerson[harness.sam] == 20002)
        #expect(byPerson[harness.priya] == 93453)
        #expect(data.weights.reduce(0, +) == 123_456)
    }

    @Test func draggingAnExactDividerLeavesTheThirdPersonAlone() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.amountText = "300"
        model.selectMethod(.exact)
        let order = try #require(model.barData).segments.map(\.id)
        model.split.exact = [order[0]: "100.01", order[1]: "99.98", order[2]: "100.01"]
        model.dragDivider(0, toFraction: 0.4, thresholdBasisPoints: 1)
        #expect(model.split.exact[order[0]] == "120.00")
        #expect(model.split.exact[order[1]] == "79.99")
        #expect(model.split.exact[order[2]] == "100.01")
        try expectBarShowsRealShares(model)
    }

    @Test func anExactStepLeavesTheThirdPersonAlone() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.amountText = "1234.56"
        model.selectMethod(.exact)
        let order = try #require(model.barData).segments.map(\.id)
        model.split.exact = [order[0]: "100.01", order[1]: "200.02", order[2]: "934.53"]
        #expect(model.adjustShare(of: order[0], increase: true))
        #expect(model.split.exact[order[0]] == "101.01")
        #expect(model.split.exact[order[1]] == "199.02")
        #expect(model.split.exact[order[2]] == "934.53")
        try expectBarShowsRealShares(model)
    }

    @Test func anAdjustDragAndStepLeaveTheThirdPersonAlone() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.amountText = "300"
        model.selectMethod(.adjustment)
        let order = try #require(model.barData).segments.map(\.id)
        model.split.adjustments = [order[0]: "10.01", order[2]: "-10.03"]
        let third = try #require(share(of: order[2], in: model))
        try expectBarShowsRealShares(model)

        model.dragDivider(0, toFraction: 0.4, thresholdBasisPoints: 1)
        #expect(share(of: order[0], in: model) == 12_000)
        #expect(share(of: order[2], in: model) == third)
        try expectBarShowsRealShares(model)

        #expect(model.adjustShare(of: order[0], increase: true))
        #expect(share(of: order[0], in: model) == 12_100)
        #expect(share(of: order[2], in: model) == third)
        try expectBarShowsRealShares(model)
    }

    @Test func aPercentDragAndStepLeaveTheThirdPersonAlone() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.amountText = "300"
        model.selectMethod(.percentage)
        let order = try #require(model.barData).segments.map(\.id)
        model.split.percent = [order[0]: "33.35", order[1]: "33.32", order[2]: "33.33"]
        let third = try #require(share(of: order[2], in: model))

        model.dragDivider(0, toFraction: 0.4, thresholdBasisPoints: 1)
        #expect(model.split.percent[order[0]] == "40")
        #expect(model.split.percent[order[2]] == "33.33")
        #expect(share(of: order[2], in: model) == third)
        try expectBarShowsRealShares(model)

        #expect(model.adjustShare(of: order[0], increase: true))
        #expect(model.split.percent[order[0]] == "41")
        #expect(model.split.percent[order[2]] == "33.33")
        #expect(share(of: order[2], in: model) == third)
        try expectBarShowsRealShares(model)
    }

    @Test func aSharesDragAndStepShowTheRealShares() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.amountText = "300"
        model.selectMethod(.shares)
        let order = try #require(model.barData).segments.map(\.id)

        // The first two trade shares; the third keeps a third of the bill.
        model.dragDivider(0, toFraction: 0.5)
        #expect(share(of: order[0], in: model) == 15_000)
        #expect(share(of: order[2], in: model) == 10_000)
        try expectBarShowsRealShares(model)

        #expect(model.adjustShare(of: order[0], increase: true))
        try expectBarShowsRealShares(model)
    }

    @Test func draggingOrSteppingAnEqualBarShowsTheRealShares() throws {
        let harness = try ExpenseFormHarness()
        let dragged = harness.filledDinner()
        dragged.amountText = "300"
        let order = try #require(dragged.barData).segments.map(\.id)
        dragged.dragDivider(0, toFraction: 0.4, thresholdBasisPoints: 1)
        #expect(dragged.split.method == .percentage)
        #expect(dragged.split.percent[order[0]] == "40")
        #expect(dragged.split.percent[order[2]] == "33.33")
        try expectBarShowsRealShares(dragged)

        let stepped = harness.filledDinner()
        stepped.amountText = "300"
        #expect(stepped.adjustShare(of: order[0], increase: true))
        #expect(stepped.split.percent[order[0]] == "34.34")
        #expect(stepped.split.percent[order[2]] == "33.33")
        try expectBarShowsRealShares(stepped)
    }

    @Test func aRefundSplitByExactAmountsDrawsItsRealProportions() throws {
        let harness = try ExpenseFormHarness()
        let fixture = harness.fixture
        let refund = Expense(
            groupID: fixture.group.id, title: "Refund", total: usd(-3000), date: fixture.clock.start,
            paidBy: fixture.me.id, split: .exact(amounts: [fixture.me.id: usd(-1000), fixture.sam.id: usd(-2000)])
        )
        try fixture.services.expenses.add(refund, extras: ExpenseExtras())
        let model = harness.editor(for: refund.id)
        let data = try #require(model.barData)
        let amounts = data.segments.filter { [fixture.me.id, fixture.sam.id].contains($0.person.id) }.compactMap(\.amount)
        #expect(Set(amounts) == [usd(-1000), usd(-2000)])
    }
}
