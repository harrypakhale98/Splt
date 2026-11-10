import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
private final class FakeReminderCenter: ReminderCenter {
    var authorized: Bool
    var grants: Bool
    var added: [ReminderRequest] = []
    var removed: [String] = []
    var removedPrefixes: [String] = []
    var asked = 0

    init(authorized: Bool = true, grants: Bool = true) {
        self.authorized = authorized
        self.grants = grants
    }

    func isAuthorized() async -> Bool { authorized }

    func requestAuthorization() async -> Bool {
        asked += 1
        authorized = grants
        return grants
    }

    func add(_ request: ReminderRequest) async throws { added.append(request) }
    func remove(identifier: String) async { removed.append(identifier) }
    func removeAll(withPrefix prefix: String) async { removedPrefixes.append(prefix) }
}

@MainActor
@Suite("Reminders")
struct ReminderTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let english = Locale(identifier: "en_US")
    private let noon = Date(timeIntervalSince1970: 1_750_000_000)

    private func scheduler(_ center: FakeReminderCenter, enabled: Bool = true, blocked: PersonID? = nil) -> ReminderScheduler {
        let visibility = FriendVisibilityStore(defaults: isolatedDefaults())
        if let blocked { visibility.set(.blocked, for: blocked) }
        return ReminderScheduler(
            center: center, notificationsEnabled: { enabled }, visibility: visibility,
            now: { noon }, calendar: calendar
        )
    }

    @Test func messageIsFriendlyAndListsEveryAmount() {
        let text = ReminderMessage.shareText(
            friendName: "Maya Chen", amounts: [usdAmount(1250), Money(minorUnits: 300, currencyCode: "EUR")],
            locale: english
        )
        #expect(text.contains("Maya"))
        #expect(!text.contains("Chen"))
        #expect(text.contains("$12.50"))
        #expect(text.contains("\u{20AC}3.00"))
        #expect(text.contains("a reminder that I'm owed"))
    }

    @Test func messageNamesASingleGroup() {
        let text = ReminderMessage.shareText(friendName: "Sam", amounts: [usdAmount(500)], groupNames: ["Lisbon Trip"], locale: english)
        #expect(text.contains("Lisbon Trip"))
        let several = ReminderMessage.shareText(friendName: "Sam", amounts: [usdAmount(500)], groupNames: ["A", "B"], locale: english)
        #expect(!several.contains("for A"))
    }

    @Test func messageSkipsAmountsYouOwe() {
        let text = ReminderMessage.shareText(friendName: "Sam", amounts: [usdAmount(500), Money(minorUnits: -900, currencyCode: "EUR")], locale: english)
        #expect(text.contains("$5.00"))
        #expect(!text.contains("9.00"))
    }

    @Test func notificationReadsGently() {
        #expect(ReminderMessage.notificationTitle(friendName: "Sam Rivera").contains("Sam"))
        let body = ReminderMessage.notificationBody(friendName: "Sam Rivera", amounts: [usdAmount(500)], locale: english)
        #expect(body.contains("$5.00"))
    }

    @Test func firesMidMorningAfterTheChosenDelay() {
        let tomorrow = ReminderDelay.tomorrow.fireDate(from: noon, calendar: calendar)
        let parts = calendar.dateComponents([.day, .hour, .minute], from: tomorrow)
        let today = calendar.dateComponents([.day], from: noon)
        #expect(parts.hour == 10 && parts.minute == 0)
        #expect(parts.day == (today.day ?? 0) + 1)
        let week = ReminderDelay.inAWeek.fireDate(from: noon, calendar: calendar)
        #expect(calendar.dateComponents([.day], from: noon, to: week).day == 6)
        #expect(ReminderDelay.inThreeDays.days == 3)
    }

    @Test func schedulesOneReminderForTheFriend() async {
        let center = FakeReminderCenter()
        let friend = Person(name: "Sam")
        let outcome = await scheduler(center).schedule(for: friend, owed: [usdAmount(500)], after: .inThreeDays)
        guard case .scheduled(let date) = outcome else { Issue.record("expected a scheduled reminder"); return }
        let request = center.added.first
        #expect(request?.identifier == ReminderScheduler.identifier(for: friend.id))
        #expect(request?.fireDate == date)
        #expect(request?.link == DeepLink.friend(friend.id.rawValue).url)
        #expect(center.asked == 0)
    }

    @Test func staysQuietUntilNotificationsAreOnInSettings() async {
        let center = FakeReminderCenter()
        let outcome = await scheduler(center, enabled: false).schedule(for: Person(name: "Sam"), owed: [usdAmount(500)], after: .tomorrow)
        #expect(outcome == .turnedOffInSettings)
        #expect(center.added.isEmpty)
        #expect(center.asked == 0)
    }

    @Test func asksTheSystemOnceAndRespectsAnAnswerOfNo() async {
        let center = FakeReminderCenter(authorized: false, grants: false)
        let outcome = await scheduler(center).schedule(for: Person(name: "Sam"), owed: [usdAmount(500)], after: .tomorrow)
        #expect(outcome == .notAllowed)
        #expect(center.asked == 1)
        #expect(center.added.isEmpty)
    }

    @Test func asksPermissionWhenNotDecidedYet() async {
        let center = FakeReminderCenter(authorized: false, grants: true)
        let outcome = await scheduler(center).schedule(for: Person(name: "Sam"), owed: [usdAmount(500)], after: .tomorrow)
        guard case .scheduled = outcome else { Issue.record("expected a scheduled reminder"); return }
        #expect(center.added.count == 1)
    }

    @Test func doesNotRemindAboutDebtsYouOwe() async {
        let center = FakeReminderCenter()
        let outcome = await scheduler(center).schedule(for: Person(name: "Sam"), owed: [usdAmount(-500)], after: .tomorrow)
        #expect(outcome == .nothingOwed)
        #expect(center.added.isEmpty)
    }

    @Test func doesNotRemindAboutBlockedPeople() async {
        let center = FakeReminderCenter()
        let friend = Person(name: "Sam")
        let outcome = await scheduler(center, blocked: friend.id).schedule(for: friend, owed: [usdAmount(500)], after: .tomorrow)
        #expect(outcome == .blocked)
        #expect(center.added.isEmpty)
    }

    @Test func cancellingRemovesTheFriendsReminder() async {
        let center = FakeReminderCenter()
        let friend = Person(name: "Sam")
        await scheduler(center).cancel(for: friend.id)
        #expect(center.removed == [ReminderScheduler.identifier(for: friend.id)])
    }

    @Test func turningNotificationsOffDropsEveryReminder() async {
        let center = FakeReminderCenter()
        await scheduler(center, enabled: false).cancelAll()
        #expect(center.removedPrefixes == [ReminderScheduler.identifierPrefix])
        #expect(ReminderScheduler.identifier(for: PersonID()).hasPrefix(ReminderScheduler.identifierPrefix))
        #expect(center.removed.isEmpty)
    }

    @Test func blockingAFriendDropsTheirReminder() async throws {
        let fixture = try Fixture()
        let center = FakeReminderCenter()
        let model = FriendsViewModel(
            services: fixture.services, visibility: FriendVisibilityStore(defaults: isolatedDefaults()),
            reminders: scheduler(center)
        )
        model.setState(.hidden, for: fixture.sam.id)
        #expect(model.reminderCancellation == nil)
        model.setState(.blocked, for: fixture.sam.id)
        await model.reminderCancellation?.value
        #expect(center.removed == [ReminderScheduler.identifier(for: fixture.sam.id)])
    }

    @Test func remindersForSettledFriendsAreDropped() async throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        fixture.services.friendsStore.refresh()
        let model = FriendsViewModel(services: fixture.services, visibility: FriendVisibilityStore(defaults: isolatedDefaults()))
        let center = FakeReminderCenter()
        await model.cancelRemindersForFriendsWhoOweNothing(using: scheduler(center))
        #expect(center.removed == [ReminderScheduler.identifier(for: fixture.priya.id)])
    }
}
