import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

@MainActor
@Suite("Schema and container")
struct SchemaTests {
    @Test func versionOneListsEveryRecordType() {
        #expect(SpltSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(SpltSchemaV1.models.count == 7)
        #expect(SpltSchemaV1.models.count == SyncRecordType.allCases.count)
    }

    @Test func migrationPlanHasOneSchemaAndNoStagesYet() {
        #expect(SpltMigrationPlan.schemas.count == 1)
        #expect(SpltMigrationPlan.schemas.first.map(ObjectIdentifier.init) == ObjectIdentifier(SpltSchemaV1.self))
        #expect(SpltMigrationPlan.stages.isEmpty)
    }

    @Test func inMemoryContainersAreIndependent() throws {
        let first = try ModelContainerFactory.make(inMemory: true)
        let second = try ModelContainerFactory.make(inMemory: true)
        first.mainContext.insert(PersonRecord(Person(name: "Only in first")))
        try first.mainContext.save()
        #expect(try first.mainContext.fetchCount(FetchDescriptor<PersonRecord>()) == 1)
        #expect(try second.mainContext.fetchCount(FetchDescriptor<PersonRecord>()) == 0)
    }

    @Test func everyRecordTypeCanBeStoredAndFetched() throws {
        let services = try DataServices.inMemory()
        let context = services.container.mainContext
        let person = Person(name: "A")
        let group = SplitGroup(name: "G", currencyCode: "USD", memberIDs: [person.id])
        let expense = Expense(groupID: group.id, title: "E", total: usdAmount(100), date: Date(), paidBy: person.id, split: .equal(participants: [person.id]))
        context.insert(PersonRecord(person))
        context.insert(GroupRecord(group))
        context.insert(ExpenseRecord(expense))
        context.insert(PaymentRecord(Payment(groupID: group.id, payer: person.id, receiver: PersonID(), amount: usdAmount(1), date: Date())))
        context.insert(CommentRecord(ExpenseComment(authorID: person.id, text: "c")))
        context.insert(ActivityRecord(ActivityEntry(event: .groupArchived)))
        context.insert(RecurringExpenseRecord(RecurringExpense(
            title: "R", total: usdAmount(100), payers: [person.id: usdAmount(100)], split: .equal(participants: [person.id]),
            rule: RecurrenceRule(frequency: .daily, startDate: Date())
        )))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PersonRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<GroupRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ExpenseRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PaymentRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CommentRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ActivityRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<RecurringExpenseRecord>()) == 1)
    }

    @Test func dataSurvivesReopeningAnOnDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Splt.store")

        let person = Person(name: "Persistent", avatarSeed: 9)
        do {
            let container = try ModelContainerFactory.make(url: url)
            let repository = SwiftDataPersonRepository(RepositoryContext(container: container))
            try repository.add(person)
        }
        let reopened = try ModelContainerFactory.make(url: url)
        let repository = SwiftDataPersonRepository(RepositoryContext(container: reopened))
        #expect(try repository.person(id: person.id)?.name == "Persistent")
        let record = try #require(try PersonRecord.find(recordName: person.id.description, in: reopened.mainContext))
        #expect(record.isDirty)
    }

    @Test func recordIDsAreUnique() throws {
        let services = try DataServices.inMemory()
        let person = Person(name: "A")
        try services.people.add(person)
        let context = services.container.mainContext
        context.insert(PersonRecord(Person(id: person.id, name: "Replaced")))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PersonRecord>()) == 1)
    }
}
