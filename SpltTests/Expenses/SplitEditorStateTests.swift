import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Split editor state")
struct SplitEditorStateTests {
    private let us = Locale(identifier: "en_US")
    private let a = PersonID(), b = PersonID(), c = PersonID()
    private var people: Set<PersonID> { [a, b, c] }

    private func definition(_ state: SplitEditorState, people: Set<PersonID>? = nil) -> SplitEditorState.Outcome {
        state.definition(participants: people ?? self.people, currencyCode: "USD", locale: us)
    }

    @Test func equalNeedsPeople() {
        let state = SplitEditorState()
        #expect(definition(state) == .definition(.equal(participants: people)))
        #expect(definition(state, people: []) == .issue(.noParticipants))
    }

    @Test func exactBlankFieldsCountAsZero() {
        var state = SplitEditorState()
        state.method = .exact
        state.exact = [a: "10", b: "5.50"]
        let expected: [PersonID: Money] = [
            a: Money(minorUnits: 1000, currencyCode: "USD"),
            b: Money(minorUnits: 550, currencyCode: "USD"),
            c: .zero(currencyCode: "USD")
        ]
        #expect(definition(state) == .definition(.exact(amounts: expected)))
    }

    @Test func exactRejectsGarbage() {
        var state = SplitEditorState()
        state.method = .exact
        state.exact = [a: "abc"]
        #expect(definition(state) == .issue(.invalidNumber))
    }

    @Test func percentagesBecomeBasisPoints() {
        var state = SplitEditorState()
        state.method = .percentage
        state.percent = [a: "50", b: "25", c: "25"]
        #expect(definition(state) == .definition(.percentages(basisPoints: [a: 5000, b: 2500, c: 2500])))
    }

    @Test func wholeSharesStayWholeAndFractionsScale() {
        var state = SplitEditorState()
        state.method = .shares
        state.weights = [a: "2", b: "1"]
        #expect(definition(state, people: [a, b, c]) == .definition(.shares(weights: [a: 2, b: 1, c: 1])))

        state.weights = [a: "1.5", b: "1", c: "1"]
        #expect(definition(state) == .definition(.shares(weights: [a: 150, b: 100, c: 100])))
    }

    @Test func adjustmentsAllowMinusAndDropZeros() {
        var state = SplitEditorState()
        state.method = .adjustment
        state.adjustments = [a: "-5", b: "", c: "0"]
        let expected: [PersonID: Money] = [a: Money(minorUnits: -500, currencyCode: "USD")]
        #expect(definition(state) == .definition(.adjustments(participants: people, adjustments: expected)))
    }

    @Test func itemizedBuildsItemsAndCharges() {
        var state = SplitEditorState()
        state.method = .itemized
        let item = ItemDraft(name: "Pasta", amountText: "12.00", assignees: [a])
        state.items = [item]
        state.taxText = "1.00"
        guard case .definition(.itemized(let itemized)) = definition(state) else {
            Issue.record("expected an itemized definition")
            return
        }
        #expect(itemized.items.first?.name == "Pasta")
        #expect(itemized.tax?.minorUnits == 100)
        #expect(itemized.tip == nil)
        #expect(state.itemizedTotal(currencyCode: "USD", locale: us)?.minorUnits == 1300)
    }

    @Test func itemizedWithoutItemsIsAnIssue() {
        var state = SplitEditorState()
        state.method = .itemized
        #expect(definition(state) == .issue(.noItems))
    }

    @Test func editorsFillFromExistingSplits() {
        let exact = SplitEditorState(definition: .exact(amounts: [a: Money(minorUnits: 2550, currencyCode: "USD")]), locale: us)
        #expect(exact.method == .exact)
        #expect(exact.exact[a] == "25.50")

        let percent = SplitEditorState(definition: .percentages(basisPoints: [a: 3333]), locale: us)
        #expect(percent.percent[a] == "33.33")

        let shares = SplitEditorState(definition: .shares(weights: [a: 2, b: 1]), locale: us)
        #expect(shares.weights[a] == "2")
    }

    @Test func rebuildingAnUnchangedSplitGivesTheSameDefinition() {
        let original: SplitDefinition = .shares(weights: [a: 2, b: 1, c: 1])
        let state = SplitEditorState(definition: original, locale: us)
        #expect(definition(state) == .definition(original))
    }
}
