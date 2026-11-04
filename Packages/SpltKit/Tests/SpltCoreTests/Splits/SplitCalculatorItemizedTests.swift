import Foundation
import Testing
@testable import SpltCore

@Suite("Itemized splits")
struct SplitCalculatorItemizedTests {
    private let a = person(1), b = person(2), c = person(3)

    private func item(_ name: String, _ amount: Int64, _ people: Set<PersonID>) -> SplitItem {
        SplitItem(name: name, amount: usd(amount), assignees: people)
    }

    private func calculate(_ split: ItemizedSplit, _ total: Int64) throws -> ShareResult {
        try SplitCalculator.calculate(.itemized(split), total: usd(total))
    }

    @Test func itemsGoToTheirAssignees() throws {
        let split = ItemizedSplit(items: [item("pizza", 2000, [a]), item("salad", 1000, [b]), item("wine", 3000, [a, b, c])])
        let result = try calculate(split, 6000)
        #expect(result.shares == [a: usd(3000), b: usd(2000), c: usd(1000)])
    }

    @Test func taxAndTipFollowWhatEachPersonOrdered() throws {
        let split = ItemizedSplit(
            items: [item("steak", 3000, [a]), item("pasta", 1000, [b])],
            tax: usd(400),
            tip: usd(800)
        )
        let result = try calculate(split, 5200)
        #expect(result.shares == [a: usd(3900), b: usd(1300)])
        #expect(result.breakdown?[a] == ShareBreakdown(items: usd(3000), tax: usd(300), tip: usd(600), discount: usd(0), total: usd(3900)))
        #expect(result.breakdown?[b] == ShareBreakdown(items: usd(1000), tax: usd(100), tip: usd(200), discount: usd(0), total: usd(1300)))
    }

    @Test func discountIsSpreadProportionally() throws {
        let split = ItemizedSplit(
            items: [item("a", 3000, [a]), item("b", 1000, [b])],
            discount: usd(800)
        )
        let result = try calculate(split, 3200)
        #expect(result.shares == [a: usd(2400), b: usd(800)])
        #expect(result.breakdown?[a]?.discount == usd(600))
    }

    @Test func everythingTogetherAddsUpExactly() throws {
        let split = ItemizedSplit(
            items: [item("x", 1099, [a, b]), item("y", 2501, [b, c]), item("z", 333, [a, b, c])],
            tax: usd(377),
            tip: usd(611),
            discount: usd(250)
        )
        let total: Int64 = 1099 + 2501 + 333 + 377 + 611 - 250
        let result = try calculate(split, total)
        #expect(result.shares.values.reduce(0) { $0 + $1.minorUnits } == total)
        for breakdown in result.breakdown!.values {
            let sum = breakdown.items.minorUnits + breakdown.tax.minorUnits + breakdown.tip.minorUnits - breakdown.discount.minorUnits
            #expect(sum == breakdown.total.minorUnits)
            #expect(breakdown.total.minorUnits >= 0)
        }
    }

    @Test func oddCentsRotateBetweenItems() throws {
        // two items of 1 cent shared by a and b: the spare cent should not always land on a
        let split = ItemizedSplit(items: [item("one", 1, [a, b]), item("two", 1, [a, b])])
        let result = try calculate(split, 2)
        #expect(result.shares == [a: usd(1), b: usd(1)])
    }

    @Test func taxOnlyBillIsSplitEquallyBetweenParticipants() throws {
        let split = ItemizedSplit(items: [item("free sample", 0, [a, b])], tax: usd(101))
        let result = try calculate(split, 101)
        #expect(result.shares == [a: usd(51), b: usd(50)])
    }

    @Test func nilExtrasCountAsZero() throws {
        let split = ItemizedSplit(items: [item("only", 500, [a])])
        let result = try calculate(split, 500)
        #expect(result.shares == [a: usd(500)])
        #expect(result.breakdown?[a]?.tax == usd(0))
    }

    @Test func totalMustMatchTheBill() {
        let split = ItemizedSplit(items: [item("only", 500, [a])], tax: usd(50))
        #expect(throws: SplitError.itemizedTotalMismatch(expected: usd(550), actual: usd(600))) {
            try calculate(split, 600)
        }
    }

    @Test func hugeItemsThrowInsteadOfCrashing() {
        let items = (0..<2).map { _ in SplitItem(name: "x", amount: usd(.max), assignees: [person(1)]) }
        #expect(throws: SplitError.overflow) {
            try SplitCalculator.calculate(.itemized(ItemizedSplit(items: items)), total: usd(.max))
        }
    }

    @Test func itemsNeedAssignees() {
        let split = ItemizedSplit(items: [item("ghost", 500, [a]), item("orphan", 500, [])])
        #expect(throws: SplitError.itemWithoutAssignees(itemIndex: 1)) { try calculate(split, 1000) }
        #expect(throws: SplitError.noParticipants) { try calculate(ItemizedSplit(items: []), 0) }
    }

    @Test func rejectsNegativeAmountsAndRefunds() {
        #expect(throws: SplitError.negativeAmount) {
            try calculate(ItemizedSplit(items: [item("bad", -500, [a])]), -500)
        }
        #expect(throws: SplitError.negativeAmount) {
            try calculate(ItemizedSplit(items: [item("ok", 500, [a])], tax: usd(-1)), 499)
        }
        #expect(throws: SplitError.negativeAmount) {
            try calculate(ItemizedSplit(items: [item("ok", 500, [a])]), -500)
        }
    }

    @Test func discountCannotExceedTheItems() {
        let split = ItemizedSplit(items: [item("only", 500, [a])], tax: usd(1000), discount: usd(600))
        #expect(throws: SplitError.discountExceedsSubtotal) { try calculate(split, 900) }
    }

    @Test func rejectsOtherCurrencies() {
        let split = ItemizedSplit(items: [SplitItem(name: "x", amount: eur(500), assignees: [a])])
        #expect(throws: SplitError.currencyMismatch(expected: "USD", found: "EUR")) { try calculate(split, 500) }
        let taxed = ItemizedSplit(items: [item("x", 500, [a])], tax: eur(10))
        #expect(throws: SplitError.currencyMismatch(expected: "USD", found: "EUR")) { try calculate(taxed, 510) }
    }

    @Test func participantsAreEveryoneWithAnItem() {
        let split = ItemizedSplit(items: [item("x", 1, [a, b]), item("y", 1, [c])])
        #expect(split.participants == [a, b, c])
        #expect(SplitDefinition.itemized(split).participants == [a, b, c])
    }
}
