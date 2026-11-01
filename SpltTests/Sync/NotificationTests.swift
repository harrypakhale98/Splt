import Foundation
import SpltCore
import Testing
@testable import Splt

/// A notification poster that keeps what it was asked to show.
@MainActor
final class FakePoster: LocalNotificationPosting {
    var authorized = true
    private(set) var posted: [LocalNotificationContent] = []
    private(set) var requested = 0

    func isAuthorized() async -> Bool { authorized }
    func requestAuthorization() async -> Bool {
        requested += 1
        return authorized
    }
    func post(_ content: LocalNotificationContent) async { posted.append(content) }
}

@MainActor
@Suite("Change messages")
struct ChangeMessagesTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let sam = PersonID()
    private let me = PersonID()
    private let group = GroupID()

    private var names: ChangeMessages.Names {
        let sam = sam
        let me = me
        let group = group
        return ChangeMessages.Names(
            me: me,
            person: { $0 == sam ? "Sam" : ($0 == me ? "Me" : nil) },
            group: { $0 == group ? "Lisbon" : nil }
        )
    }

    private func activity(
        _ event: ActivityEvent, actor: PersonID? = nil, age: TimeInterval = 60, name: String = UUID().uuidString
    ) -> SyncPayload {
        var fields = SyncFields()
        fields.set("groupID", group.rawValue)
        fields.set("actorID", (actor ?? sam).rawValue)
        fields.set("kind", event.kind.rawValue)
        fields.set("event", RecordCoding.encode(event))
        fields.set("createdAt", now.addingTimeInterval(-age))
        return SyncPayload(recordType: .activity, recordName: name, modifiedAt: now, fields: fields)
    }

    private func reference(_ title: String) -> ExpenseReference {
        ExpenseReference(id: ExpenseID(), title: title, amount: Money(minorUnits: 4200, currencyCode: "EUR"))
    }

    @Test func friendsAreToldWhatSomeoneAdded() {
        let payload = activity(.expenseAdded(reference("Dinner")), name: "A1")
        let contents = ChangeMessages.contents(for: [payload], names: names, now: now)
        #expect(contents == [LocalNotificationContent(identifier: "splt.activity.A1", title: "Splt", body: "Sam added Dinner in Lisbon")])
    }

    @Test func eachKindOfEventHasASentence() {
        let events: [(ActivityEvent, String)] = [
            (.expenseEdited(reference("Taxi")), "Sam edited Taxi in Lisbon"),
            (.expenseDeleted(reference("Taxi")), "Sam deleted Taxi in Lisbon"),
            (.paymentRecorded(PaymentReference(id: PaymentID(), payer: sam, receiver: me, amount: Money(minorUnits: 1, currencyCode: "EUR"))), "Sam recorded a payment in Lisbon"),
            (.commentAdded(expense: reference("Taxi"), text: "ha"), "Sam commented on Taxi in Lisbon"),
            (.commentAdded(expense: nil, text: "hi"), "Sam left a comment in Lisbon"),
            (.memberAdded(me), "Sam added Me in Lisbon"),
            (.groupRenamed(from: "A", to: "B"), "Sam renamed the group to B"),
        ]
        for (event, expected) in events {
            let contents = ChangeMessages.contents(for: [activity(event)], names: names, now: now)
            #expect(contents.first?.body == expected)
        }
    }

    @Test func yourOwnChangesOldChangesAndStrangersAreSkipped() {
        let own = activity(.expenseAdded(reference("Mine")), actor: me)
        let old = activity(.expenseAdded(reference("Old")), age: 2 * 3600)
        let stranger = activity(.expenseAdded(reference("Who")), actor: PersonID())
        let created = activity(.groupCreated(name: "New"))
        #expect(ChangeMessages.contents(for: [own, old, stranger, created], names: names, now: now).isEmpty)
    }

    @Test func manyChangesCollapseIntoOneSummary() {
        let batch = (0..<5).map { activity(.expenseAdded(reference("Item \($0)")), age: Double(100 - $0)) }
        let contents = ChangeMessages.contents(for: batch, names: names, now: now)
        #expect(contents.count == 1)
        #expect(contents[0].body == "5 new updates in your groups.")
    }

    @Test func messagesAreInOrderAndNeverUseDashes() {
        let first = activity(.expenseAdded(reference("First")), age: 300, name: "X1")
        let second = activity(.expenseAdded(reference("Second")), age: 100, name: "X2")
        let contents = ChangeMessages.contents(for: [second, first], names: names, now: now)
        #expect(contents.map(\.identifier) == ["splt.activity.X1", "splt.activity.X2"])
        #expect(contents.allSatisfy { !$0.body.contains("\u{2014}") && !$0.body.contains("\u{2013}") })
    }
}

@MainActor
@Suite("Remote change notifier")
struct RemoteChangeNotifierTests {
    private func report(for populated: PopulatedDevice, actor: Person) throws -> ApplyReport {
        let event = ActivityEvent.expenseAdded(ExpenseReference(
            id: ExpenseID(), title: "Dinner", amount: Money(minorUnits: 4200, currencyCode: "USD")
        ))
        var fields = SyncFields()
        fields.set("groupID", populated.group.id.rawValue)
        fields.set("actorID", actor.id.rawValue)
        fields.set("kind", event.kind.rawValue)
        fields.set("event", RecordCoding.encode(event))
        fields.set("createdAt", Date())
        return ApplyReport(inserted: [SyncPayload(
            recordType: .activity, recordName: UUID().uuidString, modifiedAt: Date(), fields: fields
        )])
    }

    private func notifier(
        _ poster: FakePoster, enabled: Bool = true, background: Bool = true
    ) -> RemoteChangeNotifier {
        RemoteChangeNotifier(poster: poster, isEnabled: { enabled }, isInBackground: { background })
    }

    @Test func postsAFriendlyNotificationInTheBackground() async throws {
        let populated = try PopulatedDevice()
        let poster = FakePoster()
        notifier(poster).notify(for: try report(for: populated, actor: populated.sam), services: populated.device.services)
        #expect(await eventually { poster.posted.count == 1 })
        #expect(poster.posted[0].body == "Sam added Dinner in Flat")
    }

    @Test func staysQuietWhenDisabledOrInTheForegroundOrNotAllowed() async throws {
        let populated = try PopulatedDevice()
        let services = populated.device.services
        let change = try report(for: populated, actor: populated.sam)
        let poster = FakePoster()
        notifier(poster, enabled: false).notify(for: change, services: services)
        notifier(poster, background: false).notify(for: change, services: services)
        poster.authorized = false
        notifier(poster).notify(for: change, services: services)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(poster.posted.isEmpty)
    }

    @Test func ignoresBatchesWithoutActivity() async throws {
        let populated = try PopulatedDevice()
        let poster = FakePoster()
        notifier(poster).notify(for: ApplyReport(), services: populated.device.services)
        notifier(poster).notify(for: ApplyReport(), services: nil)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(poster.posted.isEmpty)
    }

    @Test func requestingAuthorizationGoesToThePoster() async {
        let poster = FakePoster()
        #expect(await notifier(poster).requestAuthorization())
        #expect(poster.requested == 1)
    }
}
