import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Expense form validation")
@MainActor
struct ExpenseFormValidationTests {
    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    @Test func startsOnTheGroupsDefaults() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        #expect(model.currencyCode == "USD")
        #expect(model.payer.single == harness.me)
        #expect(model.participants == harness.fixture.everyone)
        #expect(model.split.method == .equal)
        #expect(!model.canSave)
    }

    @Test func saveWaitsForAmountThenTitle() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        #expect(model.issue == .missingAmount)
        model.amountText = "0"
        #expect(model.issue == .missingAmount)
        model.amountText = "60"
        #expect(model.issue == .missingTitle)
        model.title = "   "
        #expect(model.issue == .missingTitle)
        model.title = "Dinner"
        #expect(model.issue == nil)
        #expect(model.canSave)
        #expect(model.blockingReason == nil)
    }

    @Test func equalSplitPreviewAddsUp() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        let preview = model.sharePreview
        #expect(preview.count == 3)
        #expect(preview.allSatisfy { $0.amount == usd(2000) })
        #expect(model.statusText.contains("3 people"))
    }

    @Test func nobodyInTheSplitBlocksSaving() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        for id in harness.fixture.everyone { model.toggleParticipant(id) }
        #expect(model.issue == .noParticipants)
        #expect(model.blockingReason?.contains("split with") == true)
    }

    @Test func exactAmountsShowWhatIsLeft() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.split.method = .exact
        model.split.exact = [harness.me: "20", harness.sam: "20", harness.priya: "10"]
        #expect(model.splitRemaining == usd(1000))
        #expect(model.issue == .splitShort(usd(1000)))
        #expect(!model.canSave)

        model.split.exact[harness.priya] = "25"
        #expect(model.issue == .splitOver(usd(500)))

        model.split.exact[harness.priya] = "20"
        #expect(model.splitRemaining == usd(0))
        #expect(model.issue == nil)
    }

    @Test func percentagesMustReachOneHundred() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.split.method = .percentage
        model.split.percent = [harness.me: "50", harness.sam: "30", harness.priya: "10"]
        #expect(model.percentRemaining == 1000)
        #expect(model.issue == .percentShort(basisPoints: 1000))

        model.split.percent[harness.priya] = "30"
        #expect(model.issue == .percentOver(basisPoints: 1000))

        model.split.percent[harness.priya] = "20"
        #expect(model.issue == nil)
    }

    @Test func percentagesCanBeFilledEvenly() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.split.method = .percentage
        model.fillPercentagesEvenly()
        #expect(model.percentRemaining == 0)
        #expect(model.issue == nil)
    }

    @Test func sharesSplitInProportion() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.split.method = .shares
        model.setShareCount(2, for: harness.me)
        let byPerson = Dictionary(uniqueKeysWithValues: model.sharePreview.map { ($0.person.id, $0.amount) })
        #expect(byPerson[harness.me] == usd(3000))
        #expect(byPerson[harness.sam] == usd(1500))
        #expect(model.shareCount(for: harness.sam) == 1)

        model.setShareCount(1.5, for: harness.sam)
        let total = model.sharePreview.reduce(0) { $0 + $1.amount.minorUnits }
        #expect(total == 6000)
    }

    @Test func allZeroSharesAreRejected() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.split.method = .shares
        for id in harness.fixture.everyone { model.setShareCount(0, for: id) }
        #expect(model.issue == .noShares)
    }

    @Test func adjustmentsCannotMakeAShareNegative() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.split.method = .adjustment
        model.split.adjustments = [harness.priya: "-5"]
        #expect(model.issue == nil)
        model.split.adjustments = [harness.priya: "-500"]
        #expect(model.issue == .negativeShare(name: "Priya"))
    }

    @Test func severalPayersMustMatchTheTotal() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.setMultiplePayers(true)
        model.togglePayer(harness.sam)
        model.payer.amounts = [harness.me: "40", harness.sam: "10"]
        #expect(model.payerRemaining == usd(1000))
        #expect(model.issue == .payersShort(usd(1000)))
        model.payer.amounts[harness.sam] = "20"
        #expect(model.issue == nil)
    }

    @Test func itemizedNeedsEveryItemAssigned() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.title = "Lunch"
        model.amountText = "25"
        model.split.method = .itemized
        #expect(model.issue == .noItems)

        model.split.items = [
            ItemDraft(name: "Pasta", amountText: "12", assignees: []),
            ItemDraft(name: "Wine", amountText: "8", assignees: [harness.me])
        ]
        model.split.taxText = "2"
        model.split.tipText = "3"
        #expect(model.issue == .itemWithoutPeople(name: "Pasta"))

        model.assign(harness.sam, to: model.split.items[0].id)
        #expect(model.issue == nil)
        #expect(model.splitRemaining == usd(0))
    }

    @Test func itemizedShowsTheGapToTheTotal() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        model.title = "Lunch"
        model.amountText = "30"
        model.split.method = .itemized
        model.split.items = [ItemDraft(name: "Pasta", amountText: "12", assignees: [harness.me])]
        #expect(model.splitRemaining == usd(1800))
        #expect(model.issue == .splitShort(usd(1800)))

        model.useItemsAsTotal()
        #expect(model.amountText == "12.00")
        #expect(model.issue == nil)
    }

    @Test func refusalsReadAsFullSentences() {
        let us = Locale(identifier: "en_US")
        #expect(ExpenseFormIssue.splitShort(usd10).message(locale: us) == "$10.00 is left to assign.")
        #expect(ExpenseFormIssue.splitOver(usd10).message(locale: us) == "The split is $10.00 over the total.")
        #expect(ExpenseFormIssue.percentShort(basisPoints: 1250).message(locale: us) == "12.5% is left to assign.")
    }

    private var usd10: Money { usd(1000) }
}
