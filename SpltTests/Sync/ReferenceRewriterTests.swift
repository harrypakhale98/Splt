import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

@MainActor
@Suite("Reference rewriter")
struct ReferenceRewriterTests {
    @MainActor
    private struct World {
        let populated: PopulatedDevice
        let hana: Person
        let casey: Person
        let dinner: Expense
        var tracker: ChangeTracker { populated.device.tracker }

        /// Every person id mentioned by any record that is not a person.
        func mentions() throws -> Set<String> {
            try tracker.allNonPersonRecords().reduce(into: Set<String>()) { $0.formUnion($1.syncFields.referencedUUIDs) }
        }

        func mentioning(_ person: Person) throws -> [any SyncTracked] {
            try tracker.allNonPersonRecords().filter { $0.syncFields.referencedUUIDs.contains(person.id.description) }
        }
    }

    /// A placeholder who appears in every kind of record that can mention a person.
    private func world(withCasey: Bool = true) throws -> World {
        let populated = try PopulatedDevice()
        let services = populated.device.services
        let created = populated.device.clock.start
        let hana = Person(name: "Hana", kind: .placeholder, avatarSeed: 7, createdAt: created)
        let casey = Person(name: "Casey", avatarSeed: 8, createdAt: created)
        try services.people.add(hana)
        try services.people.add(casey)
        try services.groups.addMember(hana.id, to: populated.group.id)

        let dinner = Expense(
            groupID: populated.group.id, title: "Dinner", total: usdAmount(3000), date: created,
            paidBy: hana.id, split: .equal(participants: [populated.me.id, hana.id])
        )
        try services.expenses.add(dinner)
        var edited = dinner
        edited.title = "Dinner at Maria's"
        try services.expenses.update(edited)

        try services.payments.record(Payment(
            groupID: populated.group.id, payer: hana.id, receiver: populated.me.id, amount: usdAmount(500), date: created
        ))
        let comment = ExpenseComment(
            groupID: populated.group.id, expenseID: dinner.id, authorID: hana.id, text: "Thanks", createdAt: created
        )
        try services.comments.add(comment)
        try services.comments.toggleReaction("like", by: hana.id, on: comment.id)
        try services.recurring.add(RecurringExpense(
            groupID: populated.group.id, title: "Rent", total: usdAmount(90_000), category: .rent,
            payers: [hana.id: usdAmount(90_000)], split: .equal(participants: [populated.me.id, hana.id]),
            rule: RecurrenceRule(frequency: .monthly, startDate: created, timeZone: TimeZone(identifier: "UTC")!),
            createdBy: hana.id
        ))
        let tracker = populated.device.tracker
        let activity = ActivityRecord(
            groupID: populated.group.id.rawValue, actorID: hana.id.rawValue, kindRaw: ActivityKind.groupArchived.rawValue,
            eventData: RecordCoding.encode(ActivityEvent.groupArchived), createdAt: created
        )
        tracker.context.insert(activity)
        tracker.recordEdit(activity)
        try tracker.save()

        if withCasey { try services.groups.addMember(casey.id, to: populated.group.id) }
        return World(populated: populated, hana: hana, casey: casey, dinner: dinner)
    }

    @Test func everyKindOfRecordIsRewritten() throws {
        let world = try world()
        let before = try world.mentioning(world.hana)
        let kinds = Set(before.map(\.recordType))
        #expect(kinds == [.group, .expense, .payment, .comment, .activity, .recurringExpense])

        let result = try ReferenceRewriter(tracker: world.tracker)
            .rewrite(from: world.hana.id.rawValue, to: world.casey.id.rawValue)
        #expect(result == .rewritten(before.count))
        #expect(try world.mentions().contains(world.hana.id.description) == false)
        let after = try world.mentioning(world.casey)
        #expect(Set(after.map(\.recordType)) == kinds)
    }

    @Test func nothingIsLeftInBlobsLikeEditHistoryReactionsEventsOrTemplates() throws {
        let world = try world()
        try ReferenceRewriter(tracker: world.tracker).rewrite(from: world.hana.id.rawValue, to: world.casey.id.rawValue)
        let hana = world.hana.id.description
        for record in try world.tracker.allNonPersonRecords() {
            for (key, value) in record.syncFields.values {
                switch value {
                case .string(let text): #expect(!text.uppercased().contains(hana), "\(record.recordType).\(key)")
                case .data(let data): #expect(!String(decoding: data, as: UTF8.self).uppercased().contains(hana), "\(record.recordType).\(key)")
                default: break
                }
            }
        }
        let services = world.populated.device.services
        let expenses = try services.expenses.expenses(in: world.populated.group.id)
        #expect(expenses.allSatisfy { $0.payers.keys.contains(world.casey.id) || !$0.participants.contains(world.hana.id) })
        let payments = try services.payments.payments(in: world.populated.group.id)
        #expect(payments.first?.payer == world.casey.id)
        let template = try #require(try services.recurring.templates(in: world.populated.group.id).first)
        #expect(template.createdBy == world.casey.id)
        #expect(template.payers.keys.contains(world.casey.id))
        let comment = try #require(try services.comments.comments(on: world.dinner.id).first)
        #expect(comment.authorID == world.casey.id)
        #expect(comment.reactions.map(\.person) == [world.casey.id])
    }

    @Test func rewrittenRecordsAreMarkedForUploadAndOthersAreNot() throws {
        let world = try world()
        let cloud = FakeCloud()
        try cloud.upload(from: world.populated.device)
        let bystander = Expense(
            groupID: world.populated.group.id, title: "Solo", total: usdAmount(100), date: world.populated.device.clock.start,
            paidBy: world.populated.me.id, split: .equal(participants: [world.populated.me.id])
        )
        try world.populated.device.services.expenses.add(bystander)
        try cloud.upload(from: world.populated.device)
        #expect(try world.tracker.pendingChanges().isEmpty)

        let rewritten = Set(try world.mentioning(world.hana).map(\.recordName))
        try ReferenceRewriter(tracker: world.tracker).rewrite(from: world.hana.id.rawValue, to: world.casey.id.rawValue)
        let pending = Set(try world.tracker.pendingChanges().map(\.recordName))
        #expect(pending.isSuperset(of: rewritten))
        #expect(!pending.contains(bystander.id.description))
    }

    @Test func membershipIsMergedWhenBothPeopleWereAlreadyInTheGroup() throws {
        let world = try world()
        let group = try #require(try world.populated.device.services.groups.group(id: world.populated.group.id))
        #expect(group.memberIDs.contains(world.hana.id) && group.memberIDs.contains(world.casey.id))
        try ReferenceRewriter(tracker: world.tracker).rewrite(from: world.hana.id.rawValue, to: world.casey.id.rawValue)
        let merged = try #require(try world.populated.device.services.groups.group(id: world.populated.group.id))
        #expect(merged.memberIDs.filter { $0 == world.casey.id }.count == 1)
        #expect(!merged.memberIDs.contains(world.hana.id))
    }

    @Test func anExpenseWithBothPeopleBlocksTheWholeRewrite() throws {
        let world = try world()
        let both = Expense(
            groupID: world.populated.group.id, title: "Both", total: usdAmount(1000),
            date: world.populated.device.clock.start, paidBy: world.populated.me.id,
            split: .equal(participants: [world.hana.id, world.casey.id])
        )
        try world.populated.device.services.expenses.add(both)
        let dirtyBefore = try world.tracker.pendingChanges().count
        let result = try ReferenceRewriter(tracker: world.tracker)
            .rewrite(from: world.hana.id.rawValue, to: world.casey.id.rawValue)
        #expect(result == .blocked(records: 1))
        #expect(try world.mentions().contains(world.hana.id.description))
        #expect(try world.tracker.pendingChanges().count == dirtyBefore)
    }

    @Test func rewritingAnUnmentionedPersonChangesNothing() throws {
        let world = try world()
        let result = try ReferenceRewriter(tracker: world.tracker).rewrite(from: UUID(), to: UUID())
        #expect(result == .rewritten(0))
    }

    @Test func aHardDeletedRecordIsRewrittenWithoutBecomingASave() throws {
        let world = try world()
        let services = world.populated.device.services
        let cloud = FakeCloud()
        try cloud.upload(from: world.populated.device)
        let comment = try #require(try services.comments.comments(on: world.dinner.id).first)
        try services.comments.delete(id: comment.id)
        try ReferenceRewriter(tracker: world.tracker).rewrite(from: world.hana.id.rawValue, to: world.casey.id.rawValue)
        let pending = try world.tracker.pendingChanges().first { $0.recordName == comment.id.uuidString }
        #expect(pending?.operation == .delete)
    }
}
