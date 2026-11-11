import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

@MainActor
@Suite("Reminders in Splt")
struct InAppReminderTests {
    private let calendar = Calendar(identifier: .gregorian)

    /// A fixture where Sam uses Splt and owes you $15.00 in the shared group.
    private func samOwesMe() throws -> (Fixture, Person) {
        let fixture = try Fixture()
        var sam = fixture.sam
        sam.claimedByCloudUserID = "_sam"
        try fixture.services.people.update(sam)
        try fixture.addExpense(cents: 3_000, paidBy: fixture.me, splitBetween: [fixture.me.id, sam.id])
        return (fixture, sam)
    }

    // MARK: Who can be reminded

    @Test func reachesAFriendWhoUsesSpltInASharedGroup() throws {
        let (fixture, sam) = try samOwesMe()
        let reminder = InAppReminder(services: fixture.services, now: fixture.clock.reading)
        let state = reminder.state(for: sam, synced: [fixture.group.id])
        #expect(state == .ready([InAppReminder.Target(groupID: fixture.group.id, amounts: [usdAmount(1_500)])]))
    }

    @Test func notOfferedWithoutSpltOrASharedGroup() throws {
        let (fixture, sam) = try samOwesMe()
        let reminder = InAppReminder(services: fixture.services, now: fixture.clock.reading)
        // the group lives only on this device
        #expect(reminder.state(for: sam, synced: []) == .unavailable)
        // Sam never joined with iCloud
        #expect(reminder.state(for: fixture.sam, synced: [fixture.group.id]) == .unavailable)
        // Priya owes nothing
        var priya = fixture.priya
        priya.claimedByCloudUserID = "_priya"
        #expect(reminder.state(for: priya, synced: [fixture.group.id]) == .unavailable)
    }

    @Test func placeholdersAreNeverTargets() {
        let group = GroupID()
        let person = Person(name: "Jo", kind: .placeholder, claimedByCloudUserID: "_jo")
        let balance = FriendBalance(
            friendID: person.id, total: [usdAmount(500)], byGroup: [GroupAmounts(groupID: group, amounts: [usdAmount(500)])]
        )
        let groups = [group: SplitGroup(id: group, name: "Flat", currencyCode: "USD", memberIDs: [person.id])]
        #expect(InAppReminder.targets(friend: person, balance: balance, groups: groups, synced: [group]).isEmpty)
    }

    // MARK: Once a day

    @Test func oneReminderPerPersonPerGroupPerDay() throws {
        let (fixture, sam) = try samOwesMe()
        let reminder = InAppReminder(services: fixture.services, now: fixture.clock.reading)
        guard case .ready(let targets) = reminder.state(for: sam, synced: [fixture.group.id]) else {
            Issue.record("expected a reminder to be possible")
            return
        }
        #expect(try reminder.send(to: sam.id, targets: targets) == 1)
        #expect(reminder.state(for: sam, synced: [fixture.group.id]) == .sentToday)
        // sending again the same day writes nothing
        #expect(try reminder.send(to: sam.id, targets: targets) == 0)
        let reminders = try fixture.services.activity.entries(in: fixture.group.id, limit: 50).filter { $0.event.kind == .reminderSent }
        #expect(reminders.count == 1)
        #expect(reminders.first?.event == .reminderSent(to: sam.id, amounts: [usdAmount(1_500)]))
        #expect(reminders.first?.actorID == fixture.me.id)
        #expect(reminders.first?.isRead == true)

        fixture.clock.advance(by: 24 * 60 * 60)
        #expect(reminder.state(for: sam, synced: [fixture.group.id]).isReady)
    }

    @Test func theLimitIsPerPersonAndPerGroup() {
        let me = PersonID(), sam = PersonID(), priya = PersonID()
        let flat = GroupID(), trip = GroupID()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sent = ActivityEntry(groupID: flat, actorID: me, event: .reminderSent(to: sam, amounts: [usdAmount(100)]), createdAt: now)
        #expect(!InAppReminder.canRemind(sam, in: flat, me: me, entries: [sent], now: now, calendar: calendar))
        #expect(InAppReminder.canRemind(sam, in: trip, me: me, entries: [sent], now: now, calendar: calendar))
        #expect(InAppReminder.canRemind(priya, in: flat, me: me, entries: [sent], now: now, calendar: calendar))
        // someone else's reminder to Sam doesn't use up yours
        #expect(InAppReminder.canRemind(sam, in: flat, me: priya, entries: [sent], now: now, calendar: calendar))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        #expect(InAppReminder.canRemind(sam, in: flat, me: me, entries: [sent], now: tomorrow, calendar: calendar))
    }

    // MARK: Who sees it

    @Test func onlyTheTwoPeopleSeeTheRow() {
        let me = PersonID(), sam = PersonID(), priya = PersonID()
        let entry = ActivityEntry(actorID: priya, event: .reminderSent(to: sam, amounts: [usdAmount(100)]))
        #expect(!entry.isShown(to: me))
        #expect(entry.isShown(to: sam))
        #expect(entry.isShown(to: priya))
        #expect(!entry.isShown(to: nil))
        #expect(ActivityEntry(actorID: priya, event: .groupArchived).isShown(to: me))
    }

    @Test func theFeedSaysWhoRemindedWhom() {
        let me = PersonID(), sam = PersonID(), priya = PersonID()
        let text = GroupActivityText(currentPerson: me, names: [sam: "Sam", priya: "Priya"], locale: Locale(identifier: "en_US"))
        let amount = [Money(minorUnits: 1_200, currencyCode: "USD")]
        #expect(text.sentence(for: ActivityEntry(actorID: sam, event: .reminderSent(to: me, amounts: amount))) == "Sam reminded you: you owe $12.00")
        #expect(text.sentence(for: ActivityEntry(actorID: me, event: .reminderSent(to: sam, amounts: amount))) == "You reminded Sam about $12.00")
    }

    @Test func paymentsFilterShowsReminders() {
        #expect(ActivityTypeFilter.payments.includes(.reminderSent))
        #expect(!ActivityTypeFilter.expenses.includes(.reminderSent))
    }
}

@MainActor
@Suite("Reminder events")
struct ReminderEventCodingTests {
    @Test func aReminderRoundTrips() throws {
        let event = ActivityEvent.reminderSent(to: PersonID(), amounts: [Money(minorUnits: 1_200, currencyCode: "EUR")])
        let data = RecordCoding.encode(event)
        #expect(try RecordCoding.decode(ActivityEvent.self, from: data) == event)
        #expect(event.kind.rawValue == "reminderSent")
    }

    /// Version 1.0 decodes each row on its own and leaves out one it can't read. A reminder is a
    /// kind it doesn't know, which is exactly this case for 1.0, so its feed simply skips the row.
    @Test func aKindFromANewerVersionIsSkippedNotFatal() throws {
        let fixture = try Fixture()
        let context = fixture.services.environment.context
        let unknown = ActivityRecord(
            groupID: fixture.group.id.rawValue, actorID: fixture.sam.id.rawValue, kindRaw: "somethingNew",
            eventData: Data(#"{"somethingNew":{"to":"x","amounts":[]}}"#.utf8)
        )
        #expect(ActivityEntry(unknown) == nil)
        context.insert(unknown)
        try fixture.services.environment.save()
        try fixture.services.groups.setArchived(true, id: fixture.group.id)
        let entries = try fixture.services.activity.entries(in: fixture.group.id, limit: 50)
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.id != unknown.id })
    }

    /// What 1.0 sees: an enum without the reminder case can't decode the row, and nothing else breaks.
    @Test func aDecoderWithoutTheCaseRejectsOnlyThatRow() {
        enum OlderEvent: Codable { case groupArchived, groupRestored }
        let reminder = RecordCoding.encode(ActivityEvent.reminderSent(to: PersonID(), amounts: [usdAmount(100)]))
        let archived = RecordCoding.encode(ActivityEvent.groupArchived)
        #expect((try? RecordCoding.decode(OlderEvent.self, from: reminder)) == nil)
        #expect((try? RecordCoding.decode(OlderEvent.self, from: archived)) == .groupArchived)
    }

    @Test func aThirdPartyReminderArrivesRead() throws {
        let fixture = try Fixture()
        let tracker = fixture.services.makeChangeTracker()
        let toSam = ActivityEntry(groupID: fixture.group.id, actorID: fixture.priya.id, event: .reminderSent(to: fixture.sam.id, amounts: [usdAmount(100)]))
        let toMe = ActivityEntry(groupID: fixture.group.id, actorID: fixture.priya.id, event: .reminderSent(to: fixture.me.id, amounts: [usdAmount(100)]))
        for entry in [toSam, toMe] {
            let payload = SyncPayload(
                recordType: .activity, recordName: entry.id.uuidString, zoneName: fixture.group.id.rawValue.uuidString,
                modifiedAt: entry.createdAt,
                fields: ActivityRecord(entry).syncFields
            )
            _ = try tracker.applyRemote(payload)
        }
        let records = try fixture.services.environment.context.fetch(FetchDescriptor<ActivityRecord>())
        #expect(records.first { $0.id == toSam.id }?.isRead == true)
        #expect(records.first { $0.id == toMe.id }?.isRead == false)
        let shown = try fixture.services.activity.entries(in: fixture.group.id, limit: 50).map(\.id)
        #expect(shown.contains(toMe.id))
        #expect(!shown.contains(toSam.id))
    }
}

@MainActor
@Suite("Reminder notifications")
struct ReminderNotificationTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let sam = PersonID()
    private let me = PersonID()
    private let group = GroupID()

    private var names: ChangeMessages.Names {
        let sam = sam, me = me, group = group
        return ChangeMessages.Names(
            me: me, person: { $0 == sam ? "Sam" : nil }, group: { $0 == group ? "Flat 4B" : nil },
            locale: Locale(identifier: "en_US")
        )
    }

    private func reminder(to person: PersonID) -> SyncPayload {
        let event = ActivityEvent.reminderSent(to: person, amounts: [Money(minorUnits: 1_200, currencyCode: "USD")])
        var fields = SyncFields()
        fields.set("groupID", group.rawValue)
        fields.set("actorID", sam.rawValue)
        fields.set("kind", event.kind.rawValue)
        fields.set("event", RecordCoding.encode(event))
        fields.set("createdAt", now.addingTimeInterval(-60))
        return SyncPayload(recordType: .activity, recordName: "R1", modifiedAt: now, fields: fields)
    }

    @Test func theOneRemindedIsTold() {
        let contents = ChangeMessages.contents(for: [reminder(to: me)], names: names, now: now)
        #expect(contents.map(\.body) == ["Sam reminded you: you owe $12.00 in Flat 4B"])
        #expect(contents.first?.identifier == "splt.activity.R1")
    }

    @Test func everyoneElseHearsNothing() {
        #expect(ChangeMessages.contents(for: [reminder(to: PersonID())], names: names, now: now).isEmpty)
        let unknownMe = ChangeMessages.Names(me: nil, person: { _ in "Sam" }, group: { _ in nil })
        #expect(ChangeMessages.contents(for: [reminder(to: me)], names: unknownMe, now: now).isEmpty)
    }
}

@MainActor
@Suite("Asking for notifications")
struct NotificationAskTests {
    private func makeStore() -> UserDefaults {
        let name = "notification-ask-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    @Test func asksOnceWhenNobodyChose() {
        let store = makeStore()
        #expect(NotificationAsk.shouldAsk(defaults: store))
        NotificationAsk.markAsked(defaults: store)
        #expect(!NotificationAsk.shouldAsk(defaults: store))
    }

    @Test func respectsTheToggleEitherWay() {
        let off = makeStore()
        off.set(false, forKey: Preferences.Key.notificationsEnabled)
        #expect(!NotificationAsk.shouldAsk(defaults: off))
        let on = makeStore()
        on.set(true, forKey: Preferences.Key.notificationsEnabled)
        #expect(!NotificationAsk.shouldAsk(defaults: on))
    }

    @Test func turningOnFollowsTheSystemAnswer() async {
        let yes = makeStore()
        await NotificationAsk.turnOn(defaults: yes, requestAuthorization: { true })
        #expect(yes.bool(forKey: Preferences.Key.notificationsEnabled))
        let no = makeStore()
        await NotificationAsk.turnOn(defaults: no, requestAuthorization: { false })
        #expect(!no.bool(forKey: Preferences.Key.notificationsEnabled))
        #expect(!NotificationAsk.shouldAsk(defaults: no))
    }
}
