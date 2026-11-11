import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Default split per group")
struct DefaultSplitTests {
    private let ana = PersonID()
    private let ben = PersonID()
    private let cy = PersonID()
    private let dee = PersonID()

    // MARK: Resolving for today's members

    @Test func anEqualSplitDropsWhoLeftAndIncludesWhoJoined() throws {
        let split = DefaultSplit(method: .equal, weights: [ana: 1, ben: 0, cy: 1])
        let resolved = try #require(split.resolved(for: [ana, ben, dee]))
        #expect(resolved.method == .equal)
        #expect(resolved.participants == [ana, dee])
    }

    @Test func sharesGiveSomeoneNewOneShare() throws {
        let split = DefaultSplit(method: .shares, weights: [ana: 200, ben: 100])
        let resolved = try #require(split.resolved(for: [ana, ben, dee]))
        #expect(resolved.participants == [ana, ben, dee])
        #expect(resolved.weights == [ana: 200, ben: 100, dee: 100])
    }

    @Test func percentagesGiveSomeoneNewNothing() throws {
        let split = DefaultSplit(method: .percentages, weights: [ana: 6000, ben: 4000])
        let resolved = try #require(split.resolved(for: [ana, ben, dee]))
        #expect(resolved.participants == [ana, ben])
        #expect(resolved.weights == [ana: 6000, ben: 4000])
    }

    @Test func percentagesThatNoLongerAddUpFallBackToEqual() {
        let split = DefaultSplit(method: .percentages, weights: [ana: 6000, ben: 4000])
        #expect(split.resolved(for: [ana, cy]) == nil)
    }

    @Test func nobodyLeftFallsBackToEqual() {
        #expect(DefaultSplit(method: .equal, weights: [ana: 1]).resolved(for: []) == nil)
        #expect(DefaultSplit(method: .shares, weights: [ana: 0, ben: 0]).resolved(for: [ana, ben]) == nil)
        #expect(DefaultSplit(method: .equal, weights: [ana: 1, ben: 0]).resolved(for: [ben]) == nil)
    }

    @Test func itIsStoredAsJSONKeyedByPerson() throws {
        let split = DefaultSplit(method: .percentages, weights: [ana: 2500, ben: 7500])
        let data = RecordCoding.encode(split)
        #expect(try RecordCoding.decode(DefaultSplit.self, from: data) == split)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(ana.description))
    }

    // MARK: The editor's draft

    @Test func everyoneEquallyIsStoredAsNoDefault() {
        let draft = DefaultSplitDraft(split: nil, members: [ana, ben])
        #expect(draft.method == .equal)
        #expect(draft.isValid())
        #expect(draft.split() == nil)
    }

    @Test func aDraftReadsBackWhatItStored() {
        var draft = DefaultSplitDraft(split: nil, members: [ana, ben, cy])
        draft.method = .shares
        draft.setShareCount(2, for: ana)
        draft.setShareCount(1.5, for: ben)
        let stored = draft.split()
        #expect(stored == DefaultSplit(method: .shares, weights: [ana: 200, ben: 150, cy: 100]))
        let reopened = DefaultSplitDraft(split: stored, members: [ana, ben, cy])
        #expect(reopened.shareCount(for: ben) == 1.5)
    }

    @Test func percentagesMustAddUpBeforeTheyCanBeSaved() {
        let locale = Locale(identifier: "en_US")
        var draft = DefaultSplitDraft(split: nil, members: [ana, ben, cy], locale: locale)
        draft.method = .percentages
        draft.percent[ana] = "50"
        draft.percent[ben] = "30"
        #expect(draft.percentRemaining(locale: locale) == 2000)
        #expect(!draft.isValid(locale: locale))
        draft.fillPercentagesEvenly(locale: locale)
        #expect(draft.percentRemaining(locale: locale) == 0)
        #expect(draft.isValid(locale: locale))
    }

    @Test func aMemberWhoJoinsWhileEditingGetsTheNewcomerWeight() {
        var draft = DefaultSplitDraft(split: DefaultSplit(method: .equal, weights: [ana: 1, ben: 0]), members: [ana, ben])
        draft.setMembers([ana, ben, cy])
        #expect(draft.included == [ana, cy])
        draft.setMembers([ana, cy])
        #expect(draft.split() == nil)
    }

    // MARK: Saving and the expense form

    @Test func theRepositoryStoresTheDefault() throws {
        let fixture = try Fixture()
        let split = DefaultSplit(method: .shares, weights: [fixture.me.id: 200])
        try fixture.services.groups.setDefaultSplit(split, for: fixture.group.id)
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.defaultSplit == split)
        try fixture.services.groups.setDefaultSplit(nil, for: fixture.group.id)
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.defaultSplit == nil)
    }

    @Test func settingsSaveTheEditedSplit() throws {
        let fixture = try Fixture()
        let model = GroupSettingsViewModel(groupID: fixture.group.id, services: fixture.services)
        #expect(!model.hasFieldEdits)
        model.splitDraft.method = .shares
        model.splitDraft.setShareCount(3, for: fixture.sam.id)
        #expect(model.hasFieldEdits)
        try model.save()
        let stored = try #require(try fixture.services.groups.group(id: fixture.group.id)?.defaultSplit)
        #expect(stored.method == .shares)
        #expect(stored.weights[fixture.sam.id] == 300)
        #expect(!model.hasFieldEdits)
    }

    @Test func aNewExpenseStartsWithTheGroupsShares() throws {
        let harness = try ExpenseFormHarness()
        let fixture = harness.fixture
        try fixture.services.groups.setDefaultSplit(
            DefaultSplit(method: .shares, weights: [fixture.me.id: 200, fixture.sam.id: 100, fixture.priya.id: 0]),
            for: fixture.group.id
        )
        let model = harness.newExpense()
        #expect(model.split.method == .shares)
        #expect(model.participants == [fixture.me.id, fixture.sam.id])
        #expect(model.shareCount(for: fixture.me.id) == 2)
        #expect(!model.isDirty)
    }

    @Test func aNewExpenseStartsWithTheGroupsPercentages() throws {
        let harness = try ExpenseFormHarness()
        let fixture = harness.fixture
        try fixture.services.groups.setDefaultSplit(
            DefaultSplit(method: .percentages, weights: [fixture.me.id: 5000, fixture.sam.id: 2500, fixture.priya.id: 2500]),
            for: fixture.group.id
        )
        let model = harness.newExpense()
        model.amountText = "100"
        model.title = "Groceries"
        #expect(model.split.method == .percentage)
        #expect(model.percentRemaining == 0)
        guard case .definition(let definition) = model.split.definition(
            participants: model.participants, currencyCode: "USD", locale: Locale(identifier: "en_US")
        ) else {
            Issue.record("the default percentages should make a valid split")
            return
        }
        #expect(definition == .percentages(basisPoints: [fixture.me.id: 5000, fixture.sam.id: 2500, fixture.priya.id: 2500]))
    }

    @Test func aDefaultThatNoLongerWorksStartsEqual() throws {
        let harness = try ExpenseFormHarness()
        let fixture = harness.fixture
        // someone who held a share has left, so the rest no longer add up to 100%
        try fixture.services.groups.setDefaultSplit(
            DefaultSplit(method: .percentages, weights: [fixture.me.id: 5000, PersonID(): 5000]), for: fixture.group.id
        )
        let model = harness.newExpense()
        #expect(model.split.method == .equal)
        #expect(model.participants == fixture.everyone)
    }

    @Test func editingAnExpenseIgnoresTheDefault() throws {
        let harness = try ExpenseFormHarness()
        let fixture = harness.fixture
        let expense = try fixture.addExpense()
        try fixture.services.groups.setDefaultSplit(
            DefaultSplit(method: .shares, weights: [fixture.me.id: 300]), for: fixture.group.id
        )
        let model = harness.editor(for: expense.id)
        #expect(model.split.method == .equal)
    }
}
