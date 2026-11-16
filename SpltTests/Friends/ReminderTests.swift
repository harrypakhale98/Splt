import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
private final class FakeReminderCenter: ReminderCenter {
    var authorized: Bool
    var grants: Bool
    var added: [ReminderRequest] = []
    /// What is waiting to fire, by identifier, as the system would hold it.
    var waiting: [String: ReminderRequest] = [:]
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

    func add(_ request: ReminderRequest) async throws {
        added.append(request)
        waiting[request.identifier] = request
    }

    func remove(identifier: String) async {
        removed.append(identifier)
        waiting[identifier] = nil
    }

    func removeAll(withPrefix prefix: String) async { removedPrefixes.append(prefix) }

    func pending(withPrefix prefix: String) async -> [ReminderRequest] {
        waiting.values.filter { $0.identifier.hasPrefix(prefix) }.sorted { $0.identifier < $1.identifier }
    }
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

    private func waitingReminder(for friend: PersonID, body: String = "old") -> ReminderRequest {
        ReminderRequest(
            identifier: ReminderScheduler.identifier(for: friend), title: "Reminder", body: body,
            fireDate: noon.addingTimeInterval(86_400), link: DeepLink.friend(friend.rawValue).url
        )
    }

    private func sweeper(
        _ center: FakeReminderCenter, enabled: Bool = true, hiding: @escaping @MainActor () -> Bool = { false },
        visibility: FriendVisibilityStore = FriendVisibilityStore(defaults: isolatedDefaults()), observesApp: Bool = false
    ) -> ReminderSweeper {
        ReminderSweeper(
            center: center, notificationsEnabled: { enabled }, isHidingDetails: hiding,
            visibility: visibility, observesApp: observesApp
        )
    }

    @Test func remindersFollowTheBalancesWithoutTheFriendsTab() async throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        let gone = PersonID()
        let center = FakeReminderCenter()
        for friend in [fixture.sam.id, fixture.priya.id, gone] {
            center.waiting[ReminderScheduler.identifier(for: friend)] = waitingReminder(for: friend)
        }
        let reminders = sweeper(center)
        // the store hands every refresh over, whichever screen is open
        let store = FriendsStore(people: fixture.services.people, reminders: reminders)
        await reminders.settle()
        // Priya owes nothing and the third person no longer exists
        #expect(Set(center.removed) == [ReminderScheduler.identifier(for: fixture.priya.id), ReminderScheduler.identifier(for: gone)])
        let kept = try #require(center.waiting[ReminderScheduler.identifier(for: fixture.sam.id)])
        #expect(kept.body.contains("15"))
        #expect(kept.fireDate == noon.addingTimeInterval(86_400))
        #expect(kept.link == DeepLink.friend(fixture.sam.id.rawValue).url)

        // Sam pays you back on another device; the sync save refreshes the store
        try fixture.services.payments.record(Payment(
            groupID: fixture.group.id, payer: fixture.sam.id, receiver: fixture.me.id, amount: usdAmount(1500), date: fixture.clock.start
        ))
        store.refresh()
        await reminders.settle()
        #expect(center.waiting.isEmpty)
    }

    @Test func anUnrelatedSaveLeavesRemindersAlone() async throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        let center = FakeReminderCenter()
        center.waiting[ReminderScheduler.identifier(for: fixture.sam.id)] = waitingReminder(for: fixture.sam.id)
        let reminders = sweeper(center)
        let store = FriendsStore(people: fixture.services.people, reminders: reminders)
        await reminders.settle()
        let written = center.added.count
        store.refresh()
        await reminders.settle()
        #expect(center.added.count == written)
    }

    @Test func blockedFriendsLoseTheirReminderAndNothingHappensWhileTurnedOff() async throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        let center = FakeReminderCenter()
        center.waiting[ReminderScheduler.identifier(for: fixture.sam.id)] = waitingReminder(for: fixture.sam.id)
        let off = sweeper(center, enabled: false)
        _ = FriendsStore(people: fixture.services.people, reminders: off)
        await off.settle()
        #expect(center.removed.isEmpty && center.added.isEmpty)

        let visibility = FriendVisibilityStore(defaults: isolatedDefaults())
        visibility.set(.blocked, for: fixture.sam.id)
        let on = sweeper(center, visibility: visibility)
        _ = FriendsStore(people: fixture.services.people, reminders: on)
        await on.settle()
        #expect(center.removed == [ReminderScheduler.identifier(for: fixture.sam.id)])
    }

    @Test func turningTheLockOnOrOffWritesPendingRemindersAgain() async throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        let center = FakeReminderCenter()
        center.waiting[ReminderScheduler.identifier(for: fixture.sam.id)] = waitingReminder(for: fixture.sam.id)
        @MainActor final class Lock { var on = false }
        let lock = Lock()
        let reminders = sweeper(center, hiding: { lock.on }, observesApp: true)
        _ = FriendsStore(people: fixture.services.people, reminders: reminders)
        await reminders.settle()
        let written = center.added.count
        lock.on = true
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        #expect(await eventually { center.added.count == written + 1 })
        await reminders.settle()
        #expect(center.added.last?.identifier == ReminderScheduler.identifier(for: fixture.sam.id))
        lock.on = false
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        #expect(await eventually { center.added.count == written + 2 })
    }

    @Test func lockedRemindersSayNothingAboutAmounts() {
        let store = isolatedDefaults()
        store.set(true, forKey: Preferences.Key.biometricLockEnabled)
        let request = NotificationPrivacy.apply(to: waitingReminder(for: PersonID(), body: "Sam may still owe you $15.00."), store: store)
        #expect(request.title == "Splt")
        #expect(request.body == NotificationPrivacy.genericBody)
    }

    @Test func turningNotificationsOffFindsEveryPaymentNotification() {
        let payment = PaymentNotifier.identifier(for: UUID())
        let wrapUp = PaymentNotifier.wrapUpPrefix + UUID().uuidString
        let ids = [payment, wrapUp, PaymentNotifier.digestID, ReminderScheduler.identifier(for: PersonID()), "splt.activity.A1"]
        #expect(PaymentNotifier.scheduledByThis(among: ids) == [payment, wrapUp, PaymentNotifier.digestID])
    }

    @Test func reminderIdentifiersNameTheirFriend() {
        let friend = PersonID()
        #expect(ReminderScheduler.friend(in: ReminderScheduler.identifier(for: friend)) == friend)
        #expect(ReminderScheduler.friend(in: "splt.activity.A1") == nil)
    }
}
