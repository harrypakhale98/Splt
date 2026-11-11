import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

@MainActor
@Suite("Unread count and reminder expiry")
struct ReminderExpiryTests {
    private let week: TimeInterval = 7 * 24 * 60 * 60

    @Test func aRowThisVersionCantReadIsNotCounted() throws {
        let fixture = try Fixture()
        let before = try fixture.services.activity.unreadCount()
        let unknown = ActivityRecord(
            groupID: fixture.group.id.rawValue, actorID: fixture.sam.id.rawValue, kindRaw: "somethingNew",
            eventData: Data(#"{"somethingNew":{}}"#.utf8)
        )
        let known = ActivityEntry(groupID: fixture.group.id, actorID: fixture.sam.id, event: .groupArchived)
        fixture.services.environment.context.insert(unknown)
        fixture.services.environment.context.insert(ActivityRecord(known))
        try fixture.services.environment.save()
        #expect(try fixture.services.activity.unreadCount() == before + 1)
    }

    @Test func aReminderBetweenOthersIsNotCounted() throws {
        let fixture = try Fixture()
        let before = try fixture.services.activity.unreadCount()
        let entry = ActivityEntry(
            groupID: fixture.group.id, actorID: fixture.priya.id,
            event: .reminderSent(to: fixture.sam.id, amounts: [usdAmount(100)]), isRead: false
        )
        fixture.services.environment.context.insert(ActivityRecord(entry))
        try fixture.services.environment.save()
        #expect(try fixture.services.activity.unreadCount() == before)
    }

    @Test func onlyTheSenderRemovesWeekOldReminders() throws {
        let fixture = try Fixture()
        let context = fixture.services.environment.context
        try fixture.services.activity.recordReminder(to: fixture.sam.id, amounts: [usdAmount(1_500)], in: fixture.group.id)
        let mine = try #require(try context.fetch(FetchDescriptor<ActivityRecord>()).first { $0.kindRaw == "reminderSent" })
        // a reminder Sam sent you, and one of yours that is only a day old
        let theirs = ActivityRecord(ActivityEntry(
            groupID: fixture.group.id, actorID: fixture.sam.id,
            event: .reminderSent(to: fixture.me.id, amounts: [usdAmount(500)]), createdAt: mine.createdAt
        ))
        context.insert(theirs)
        let recent = ActivityRecord(ActivityEntry(
            groupID: fixture.group.id, actorID: fixture.me.id,
            event: .reminderSent(to: fixture.priya.id, amounts: [usdAmount(500)]),
            createdAt: mine.createdAt.addingTimeInterval(6 * 24 * 60 * 60)
        ))
        context.insert(recent)
        let archived = ActivityRecord(ActivityEntry(
            groupID: fixture.group.id, actorID: fixture.me.id, event: .groupArchived, createdAt: mine.createdAt
        ))
        context.insert(archived)
        // pretend all of them reached the server, so removing one has to sync
        for record in [mine, theirs, recent, archived] {
            record.systemFields = Data([1])
            record.isDirty = false
        }
        try fixture.services.environment.save()

        let now = mine.createdAt.addingTimeInterval(week + 60)
        #expect(ReminderExpiry.run(services: fixture.services, now: now) == 1)
        #expect(mine.deletedAt != nil)
        #expect(mine.isDirty)
        #expect(mine.pendingOperation == .delete)
        #expect(theirs.deletedAt == nil)
        #expect(recent.deletedAt == nil)
        #expect(archived.deletedAt == nil)
        #expect(!(try fixture.services.activity.entries(in: fixture.group.id, limit: 50).contains { $0.id == mine.id }))
        // a second run finds nothing new
        #expect(ReminderExpiry.run(services: fixture.services, now: now) == 0)

        // once the server confirmed the deletion, the tombstone is purged like any other
        mine.isDirty = false
        mine.pendingOperation = nil
        try fixture.services.environment.save()
        let purged = try fixture.services.environment.tracker.purgeConfirmedTombstones(
            olderThan: try #require(mine.deletedAt).addingTimeInterval(1)
        )
        #expect(purged == 1)
        #expect(try context.fetch(FetchDescriptor<ActivityRecord>()).filter { $0.kindRaw == "reminderSent" }.count == 2)
    }
}
