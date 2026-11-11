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

    /// Stores a claim the way sync does when it arrives from someone else's device.
    private func receiveClaim(
        _ fixture: Fixture, _ person: PersonID, _ items: Set<UUID>, on expense: Expense, deleted: Bool = false
    ) throws {
        let tracker = fixture.services.makeChangeTracker()
        let record = ItemClaimRecord(
            groupID: fixture.group.id.rawValue, expenseID: expense.id.rawValue, personID: person.rawValue,
            itemIDs: Array(items), createdAt: fixture.clock.start
        )
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
    }
}
