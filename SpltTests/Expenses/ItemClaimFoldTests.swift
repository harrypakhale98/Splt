import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Item picks")
struct ItemClaimFoldTests {
    private let pizza = UUID()
    private let beer = UUID()
    private let salad = UUID()

    private func split(_ fixture: Fixture, tax: Int64? = nil) -> ItemizedSplit {
        ItemizedSplit(
            items: [
                SplitItem(id: pizza, name: "Pizza", amount: usdAmount(2000), assignees: fixture.everyone),
                SplitItem(id: beer, name: "Beer", amount: usdAmount(600), assignees: fixture.everyone),
                SplitItem(id: salad, name: "Salad", amount: usdAmount(400), assignees: [fixture.me.id])
            ],
            tax: tax.map(usdAmount)
        )
    }

    private func claim(_ person: PersonID, _ items: Set<UUID>, on expense: ExpenseID) -> ItemClaim {
        ItemClaim(
            id: ItemClaimRecord.claimID(expenseID: expense.rawValue, personID: person.rawValue),
            groupID: nil, expenseID: expense, personID: person, itemIDs: items, modifiedAt: Date()
        )
    }

    /// An itemized expense in the fixture's group, added by `creator`.
    private func addItemized(_ fixture: Fixture, by creator: Person? = nil, tax: Int64? = nil) throws -> Expense {
        let split = split(fixture, tax: tax)
        let total = split.items.reduce(0) { $0 + $1.amount.minorUnits } + (tax ?? 0)
        let expense = Expense(
            groupID: fixture.group.id, title: "Night out", total: usdAmount(total), date: fixture.clock.start,
            paidBy: fixture.me.id, split: .itemized(split)
        )
        if let creator, creator.id != fixture.me.id {
            try SwiftDataExpenseRepository(fixture.services.environment).insertBatch([expense], createdBy: creator.id)
            try fixture.services.environment.save()
        } else {
            try fixture.services.expenses.add(expense)
        }
        return expense
    }

    /// Stores a claim the way sync does when it arrives from someone else's device, made just now.
    private func receiveClaim(
        _ fixture: Fixture, _ person: PersonID, _ items: Set<UUID>, on expense: Expense, deleted: Bool = false
    ) throws {
        let tracker = fixture.services.makeChangeTracker()
        let record = ItemClaimRecord(
            groupID: fixture.group.id.rawValue, expenseID: expense.id.rawValue, personID: person.rawValue,
            itemIDs: Array(items), createdAt: fixture.clock.start
        )
        record.modifiedAt = fixture.clock.now()
        tracker.context.insert(record)
        if deleted { tracker.softDelete(record) }
        try tracker.save()
    }

    private func items(of expense: ExpenseID, in fixture: Fixture) throws -> [UUID: Set<PersonID>] {
        let stored = try #require(try fixture.services.expenses.expense(id: expense))
        guard case .itemized(let split) = stored.split else { return [:] }
        return Dictionary(uniqueKeysWithValues: split.items.map { ($0.id, $0.assignees) })
    }

    // MARK: Rules

    @Test func aClaimantJoinsTheirItemsAndLeavesOtherPickedOnes() throws {
        let fixture = try Fixture()
        let id = ExpenseID()
        let result = ItemClaimFold.folded(split(fixture), people: fixture.everyone, claims: [
            claim(fixture.sam.id, [beer], on: id),
            claim(fixture.priya.id, [pizza], on: id)
        ])
        let byID = Dictionary(uniqueKeysWithValues: result.items.map { ($0.id, $0.assignees) })
        #expect(byID[pizza] == [fixture.me.id, fixture.priya.id])
        #expect(byID[beer] == [fixture.me.id, fixture.sam.id])
    }

    @Test func itemsNobodyPickedKeepTheirPeople() throws {
        let fixture = try Fixture()
        let id = ExpenseID()
        let result = ItemClaimFold.folded(split(fixture), people: fixture.everyone, claims: [
            claim(fixture.sam.id, [beer], on: id)
        ])
        let byID = Dictionary(uniqueKeysWithValues: result.items.map { ($0.id, $0.assignees) })
        #expect(byID[pizza] == fixture.everyone)
        #expect(byID[salad] == [fixture.me.id])
    }

    @Test func pickingAnUnassignedItemAddsYou() throws {
        let fixture = try Fixture()
        let id = ExpenseID()
        let result = ItemClaimFold.folded(split(fixture), people: fixture.everyone, claims: [
            claim(fixture.sam.id, [salad, beer], on: id)
        ])
        let byID = Dictionary(uniqueKeysWithValues: result.items.map { ($0.id, $0.assignees) })
        #expect(byID[salad] == [fixture.me.id, fixture.sam.id])
    }

    @Test func claimsOfOutsidersMissingItemsAndForeignIDsAreIgnored() throws {
        let fixture = try Fixture()
        let id = ExpenseID()
        let outsider = PersonID()
        var forged = claim(fixture.sam.id, [pizza], on: id)
        forged.id = UUID()
        let original = split(fixture)
        let result = ItemClaimFold.folded(original, people: fixture.everyone, claims: [
            claim(outsider, [pizza], on: id),
            claim(fixture.priya.id, [UUID()], on: id),
            forged
        ])
        #expect(result == original)
    }

    // MARK: Folding on the creator's device

    @Test func theCreatorsDeviceFoldsArrivingPicksOnce() throws {
        let fixture = try Fixture()
        let expense = try addItemized(fixture)
        try receiveClaim(fixture, fixture.sam.id, [beer], on: expense)
        try receiveClaim(fixture, fixture.priya.id, [pizza, salad], on: expense)

        #expect(try fixture.services.claims.foldClaims(inGroups: [fixture.group.id]) == 1)
        let items = try items(of: expense.id, in: fixture)
        #expect(items[pizza] == [fixture.me.id, fixture.priya.id])
        #expect(items[beer] == [fixture.me.id, fixture.sam.id])
        #expect(items[salad] == [fixture.me.id, fixture.priya.id])
        let edit = try #require(try fixture.services.expenses.edits(of: expense.id).last)
        #expect(edit.editChanges.map(\.field) == [.split])

        // a second run, as after another sync or launch, writes nothing
        let record = try #require(try ExpenseRecord.find(recordName: expense.id.description, in: fixture.services.environment.context))
        record.isDirty = false
        let modified = record.modifiedAt
        let activity = try fixture.services.activity.entries(in: fixture.group.id, limit: 100).count
        #expect(try fixture.services.claims.foldClaims(inGroups: nil) == 0)
        #expect(record.modifiedAt == modified)
        #expect(!record.isDirty)
        #expect(try fixture.services.activity.entries(in: fixture.group.id, limit: 100).count == activity)
        #expect(try fixture.services.expenses.details(id: expense.id)?.history.count == 1)
    }

    @Test func everyDeviceGivesTheSameFoldTheSameEntry() throws {
        let fixture = try Fixture()
        let expense = try addItemized(fixture)
        try receiveClaim(fixture, fixture.sam.id, [beer], on: expense)
        try receiveClaim(fixture, fixture.priya.id, [pizza, salad], on: expense)
        #expect(try fixture.services.claims.foldClaims(inGroups: nil) == 1)
        let stored = try #require(try fixture.services.expenses.expense(id: expense.id))
        guard case .itemized(let after) = stored.split else { Issue.record("not split by item"); return }

        // the id comes from the expense and the fold alone, not from this device or the time
        let edit = try #require(try fixture.services.expenses.edits(of: expense.id).last)
        #expect(edit.id == ItemClaimFold.editID(expense: expense.id, from: split(fixture), to: after))
        #expect(edit.id != ItemClaimFold.editID(expense: ExpenseID(rawValue: UUID()), from: split(fixture), to: after))
        #expect(edit.id != ItemClaimFold.editID(expense: expense.id, from: after, to: split(fixture)))
    }

    @Test func aFoldFromTheCreatorsOtherDeviceIsNotLoggedTwice() throws {
        let fixture = try Fixture()
        let expense = try addItemized(fixture)
        try receiveClaim(fixture, fixture.sam.id, [beer], on: expense)
        try receiveClaim(fixture, fixture.priya.id, [pizza, salad], on: expense)
        let record = try #require(try ExpenseRecord.find(recordName: expense.id.description, in: fixture.services.environment.context))
        let stored = try #require(try fixture.services.expenses.expense(id: expense.id))
        let folded = try #require(ItemClaimFold.folding(
            try fixture.services.claims.claims(on: expense.id), into: stored, modifiedAt: record.modifiedAt
        ))
        guard case .itemized(let after) = folded.split else { Issue.record("not split by item"); return }
        let id = ItemClaimFold.editID(expense: expense.id, from: split(fixture), to: after)
        // the entry the creator's other device wrote for the same fold arrives before its edit
        try fixture.services.environment.log(
            .expenseEdited(SwiftDataExpenseRepository.reference(folded)), groupID: fixture.group.id, actor: fixture.me.id, id: id
        )
        try fixture.services.environment.save()
        let count = try fixture.services.activity.entries(in: fixture.group.id, limit: 100).count

        #expect(try fixture.services.claims.foldClaims(inGroups: nil) == 1)
        #expect(try items(of: expense.id, in: fixture)[pizza] == [fixture.me.id, fixture.priya.id])
        #expect(try fixture.services.activity.entries(in: fixture.group.id, limit: 100).count == count)
        #expect(try fixture.services.expenses.edits(of: expense.id).map(\.id) == [id])
    }

    @Test func aCreatorsLaterEditWinsUntilANewerClaim() throws {
        let fixture = try Fixture()
        let expense = try addItemized(fixture)
        try receiveClaim(fixture, fixture.sam.id, [beer], on: expense)
        try receiveClaim(fixture, fixture.priya.id, [pizza], on: expense)
        try fixture.services.claims.foldClaims(inGroups: nil)
        #expect(try items(of: expense.id, in: fixture)[pizza] == [fixture.me.id, fixture.priya.id])

        // the creator puts Sam back on the pizza by hand, after his claim
        var edited = try #require(try fixture.services.expenses.expense(id: expense.id))
        guard case .itemized(var split) = edited.split else { Issue.record("not itemized"); return }
        split.items[0].assignees.insert(fixture.sam.id)
        edited.split = .itemized(split)
        try fixture.services.expenses.update(edited)
        let history = try fixture.services.expenses.details(id: expense.id)?.history.count

        // a later fold, as when the app comes to the front, leaves that edit alone
        #expect(try fixture.services.claims.foldClaims(inGroups: nil) == 0)
        #expect(try items(of: expense.id, in: fixture)[pizza] == fixture.everyone)
        #expect(try fixture.services.expenses.details(id: expense.id)?.history.count == history)

        // Sam picks again after that edit, so his new picks win
        try receiveClaim(fixture, fixture.sam.id, [beer, salad], on: expense)
        #expect(try fixture.services.claims.foldClaims(inGroups: nil) == 1)
        let items = try items(of: expense.id, in: fixture)
        #expect(items[pizza] == [fixture.me.id, fixture.priya.id])
        #expect(items[salad] == [fixture.me.id, fixture.sam.id])
    }

    @Test func nobodyIsTakenOffAnItemTheyAreLastOn() throws {
        let fixture = try Fixture()
        let id = ExpenseID()
        let old = claim(fixture.sam.id, [salad], on: id)
        var new = claim(fixture.me.id, [pizza], on: id)
        new.modifiedAt = old.modifiedAt.addingTimeInterval(60)
        let result = ItemClaimFold.folded(
            split(fixture), people: fixture.everyone, claims: [old, new], since: old.modifiedAt.addingTimeInterval(1)
        )
        let byID = Dictionary(uniqueKeysWithValues: result.items.map { ($0.id, $0.assignees) })
        #expect(byID[salad] == [fixture.me.id])
    }

    @Test func deletedClaimsDoNotCount() throws {
        let fixture = try Fixture()
        let expense = try addItemized(fixture)
        try receiveClaim(fixture, fixture.sam.id, [beer], on: expense, deleted: true)
        #expect(try fixture.services.claims.foldClaims(inGroups: nil) == 0)
        #expect(try items(of: expense.id, in: fixture)[pizza] == fixture.everyone)
    }

    @Test func onlyTheCreatorsDeviceFolds() throws {
        let fixture = try Fixture()
        let expense = try addItemized(fixture, by: fixture.sam)
        try receiveClaim(fixture, fixture.priya.id, [pizza], on: expense)
        #expect(try fixture.services.claims.foldClaims(inGroups: nil) == 0)
        #expect(try items(of: expense.id, in: fixture)[pizza] == fixture.everyone)
    }

    @Test func taxFollowsTheFoldedItems() throws {
        let fixture = try Fixture()
        let expense = try addItemized(fixture, tax: 300)
        try receiveClaim(fixture, fixture.sam.id, [beer], on: expense)
        try receiveClaim(fixture, fixture.priya.id, [pizza], on: expense)
        try fixture.services.claims.foldClaims(inGroups: nil)
        let stored = try #require(try fixture.services.expenses.expense(id: expense.id))
        let result = try stored.shares()
        // Sam has half the beer, $3.00 of $30.00 in items, so a tenth of the tax
        #expect(result.breakdown?[fixture.sam.id]?.items == usdAmount(300))
        #expect(result.breakdown?[fixture.sam.id]?.tax == usdAmount(30))
        #expect(result.shares.values.reduce(0) { $0 + $1.minorUnits } == 3300)
    }

    // MARK: Picking

    @Test func pickingOnSomeoneElsesExpenseOnlyWritesYourClaim() throws {
        let fixture = try Fixture()
        let expense = try addItemized(fixture, by: fixture.sam)
        try fixture.services.claims.setMyPicks([salad], on: expense.id)

        let claims = try fixture.services.claims.claims(on: expense.id)
        #expect(claims.map(\.personID) == [fixture.me.id])
        #expect(claims.first?.itemIDs == [salad])
        #expect(try fixture.services.expenses.expense(id: expense.id) == expense)
        #expect(try fixture.services.expenses.details(id: expense.id)?.history.isEmpty == true)

        // picking again changes the same claim
        try fixture.services.claims.setMyPicks([salad, beer], on: expense.id)
        #expect(try fixture.services.claims.claims(on: expense.id).map(\.itemIDs) == [[salad, beer]])
    }

    @Test func pickingOnYourOwnExpenseFoldsAtOnce() throws {
        let fixture = try Fixture()
        let expense = try addItemized(fixture)
        try receiveClaim(fixture, fixture.sam.id, [beer], on: expense)
        try fixture.services.claims.setMyPicks([salad], on: expense.id)
        let items = try items(of: expense.id, in: fixture)
        #expect(items[salad] == [fixture.me.id])
        #expect(items[beer] == [fixture.sam.id, fixture.priya.id])
    }

    @Test func theDetailScreenShowsPicksAndWaitsForTheCreator() throws {
        let fixture = try Fixture()
        try fixture.services.people.claim(fixture.sam.id, cloudUserID: "_sam")
        let expense = try addItemized(fixture, by: fixture.sam)
        try receiveClaim(fixture, fixture.priya.id, [pizza], on: expense)
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: Locale(identifier: "en_US"))
        #expect(model.canPickItems)
        #expect(model.pickers(of: pizza) == [fixture.priya.id])
        // Priya already shares the pizza, so the split has nothing to wait for
        #expect(model.waitingForName == nil)

        try receiveClaim(fixture, fixture.priya.id, [salad], on: expense)
        model.reload()
        #expect(model.waitingForName == "Sam")
        #expect(model.myPicks == [pizza, beer, salad])

        // an edit of the expense after the claim settles it
        var edited = expense
        edited.title = "Late night"
        try fixture.services.expenses.update(edited)
        model.reload()
        #expect(model.waitingForName == nil)
    }

    /// The result must not depend on how the two people's ids happen to sort.
    @Test(arguments: [false, true])
    func aPickedItemMovesWholeWhateverTheIdOrder(swapped: Bool) {
        let low = PersonID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let high = PersonID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let (alex, blair) = swapped ? (high, low) : (low, high)
        let expense = ExpenseID(rawValue: UUID())
        let split = ItemizedSplit(items: [
            SplitItem(id: pizza, name: "Pizza", amount: usdAmount(2000), assignees: [alex]),
            SplitItem(id: beer, name: "Beer", amount: usdAmount(600), assignees: [blair])
        ])
        // Alex had only the beer and Blair only the pizza
        let folded = ItemClaimFold.folded(split, people: [alex, blair], claims: [
            claim(alex, [beer], on: expense), claim(blair, [pizza], on: expense)
        ])
        #expect(folded.items.first { $0.id == pizza }?.assignees == [blair])
        #expect(folded.items.first { $0.id == beer }?.assignees == [alex])
    }
}
