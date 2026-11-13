import Foundation
import SwiftUI
import Testing
@testable import Splt

private final class FakeAuthenticator: OwnerAuthenticating, @unchecked Sendable {
    var available = true
    var succeeds = true
    var passcodeMissing = false
    private(set) var attempts = 0

    func isAvailable() -> Bool { available }
    func isPasscodeMissing() -> Bool { passcodeMissing }
    func kind() -> BiometricKind { .faceID }
    func authenticate(reason: String) async -> Bool {
        attempts += 1
        return succeeds
    }
}

@MainActor
@Suite("App lock")
struct UIAppLockTests {
    private func makeStore(enabled: Bool) -> UserDefaults {
        let suite = "splt.tests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        store.set(enabled, forKey: Preferences.Key.biometricLockEnabled)
        return store
    }

    @Test func theLockIsOffByDefault() {
        #expect(!Preferences(store: makeStore(enabled: false)).biometricLockEnabled)
        let lock = AppLock(authenticator: FakeAuthenticator(), store: makeStore(enabled: false))
        #expect(!lock.isLocked)
        #expect(!lock.isCovering(phase: .background))
    }

    @Test func itStartsLockedWhenTurnedOn() {
        let lock = AppLock(authenticator: FakeAuthenticator(), store: makeStore(enabled: true))
        #expect(lock.isLocked)
        #expect(lock.isCovering(phase: .active))
    }

    @Test func aSuccessfulFaceOpensIt() async {
        let lock = AppLock(authenticator: FakeAuthenticator(), store: makeStore(enabled: true))
        await lock.unlock()
        #expect(!lock.isLocked)
        #expect(!lock.isCovering(phase: .active))
    }

    @Test func aFailedOrCancelledFaceLeavesItLocked() async {
        let authenticator = FakeAuthenticator()
        authenticator.succeeds = false
        let lock = AppLock(authenticator: authenticator, store: makeStore(enabled: true))
        await lock.unlock()
        #expect(lock.isLocked)
    }

    @Test func itIsCoveredWhenNotInFrontButOnlyLockedAfterAWhile() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let lock = AppLock(authenticator: FakeAuthenticator(), store: makeStore(enabled: true), now: { clock })
        await lock.unlock()

        #expect(lock.isCovering(phase: .inactive))

        lock.didLeave()
        clock.addTimeInterval(AppLock.gracePeriod - 1)
        #expect(lock.didReturn())
        #expect(!lock.isLocked)

        lock.didLeave()
        clock.addTimeInterval(AppLock.gracePeriod)
        #expect(lock.didReturn())
        #expect(lock.isLocked)
    }

    @Test func theFaceIDPromptComesOncePerOpeningOrReturn() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let authenticator = FakeAuthenticator()
        authenticator.succeeds = false
        let lock = AppLock(authenticator: authenticator, store: makeStore(enabled: true), now: { clock })

        // opening the app asks once; cancelling it must not ask again until the app is left and returned to
        #expect(lock.takePendingPrompt())
        await lock.unlock()
        #expect(!lock.takePendingPrompt())

        lock.didLeave()
        clock.addTimeInterval(1)
        lock.didReturn()
        #expect(lock.isLocked)
        #expect(lock.takePendingPrompt())
        #expect(!lock.takePendingPrompt())
    }

    @Test func noPromptWhenTheLockIsOff() {
        let lock = AppLock(authenticator: FakeAuthenticator(), store: makeStore(enabled: false))
        #expect(!lock.takePendingPrompt())
    }

    @Test func pausingWithoutLeavingNeverLocks() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let lock = AppLock(authenticator: FakeAuthenticator(), store: makeStore(enabled: true), now: { clock })
        await lock.unlock()
        clock.addTimeInterval(3_600)
        #expect(!lock.didReturn())
        #expect(!lock.isLocked)
    }

    @Test func aLockThatIsOffNeverLocksOnReturn() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let lock = AppLock(authenticator: FakeAuthenticator(), store: makeStore(enabled: false), now: { clock })
        lock.didLeave()
        clock.addTimeInterval(3_600)
        lock.didReturn()
        #expect(!lock.isLocked)
    }

    @Test func turningItOnNeedsAFaceAndAPasscode() async {
        let authenticator = FakeAuthenticator()
        let lock = AppLock(authenticator: authenticator, store: makeStore(enabled: false))
        #expect(await lock.confirmEnabling())

        authenticator.succeeds = false
        #expect(!(await lock.confirmEnabling()))

        authenticator.succeeds = true
        authenticator.available = false
        let attempts = authenticator.attempts
        #expect(!(await lock.confirmEnabling()))
        #expect(authenticator.attempts == attempts)
    }

    // MARK: Passcode removed

    @Test func aPhoneWithoutAPasscodeOpensUnlockedAndTurnsTheLockOff() {
        let authenticator = FakeAuthenticator()
        authenticator.passcodeMissing = true
        let store = makeStore(enabled: true)
        let lock = AppLock(authenticator: authenticator, store: store)
        #expect(!lock.isLocked)
        #expect(!lock.isEnabled)
        #expect(!Preferences(store: store).biometricLockEnabled)
    }

    @Test func removingThePasscodeWhileAwayReleasesTheLock() async {
        let authenticator = FakeAuthenticator()
        let store = makeStore(enabled: true)
        let lock = AppLock(authenticator: authenticator, store: store)
        await lock.unlock()
        lock.didLeave()
        authenticator.passcodeMissing = true
        lock.didReturn()
        #expect(!lock.isLocked)
        #expect(!lock.isEnabled)
    }

    @Test func aFailedUnlockOnAPhoneThatLostItsPasscodeReleasesTheLock() async {
        let authenticator = FakeAuthenticator()
        authenticator.succeeds = false
        let lock = AppLock(authenticator: authenticator, store: makeStore(enabled: true))
        authenticator.passcodeMissing = true
        await lock.unlock()
        #expect(!lock.isLocked)
        #expect(!lock.isEnabled)
    }

    // MARK: Turning it off

    @Test func turningItOffNeedsAFaceUnlessNothingCanGiveOne() async {
        let authenticator = FakeAuthenticator()
        let lock = AppLock(authenticator: authenticator, store: makeStore(enabled: true))
        #expect(await lock.confirmDisabling())

        authenticator.succeeds = false
        #expect(!(await lock.confirmDisabling()))

        authenticator.available = false
        let attempts = authenticator.attempts
        #expect(await lock.confirmDisabling())
        #expect(authenticator.attempts == attempts)
    }

    // MARK: Siri and Shortcuts

    @Test func intentsRunFreelyWhileTheLockIsOff() async throws {
        let authenticator = FakeAuthenticator()
        authenticator.succeeds = false
        try await IntentLock.requireUnlocked(store: makeStore(enabled: false), authenticator: authenticator)
        #expect(authenticator.attempts == 0)
    }

    @Test func intentsNeedAFaceWhileTheLockIsOn() async throws {
        let authenticator = FakeAuthenticator()
        try await IntentLock.requireUnlocked(store: makeStore(enabled: true), authenticator: authenticator)
        #expect(authenticator.attempts == 1)

        authenticator.succeeds = false
        let store = makeStore(enabled: true)
        await #expect(throws: IntentError.self) {
            try await IntentLock.requireUnlocked(store: store, authenticator: authenticator)
        }
    }

    @Test func intentsDoNotStrandAPhoneThatLostItsPasscode() async throws {
        let authenticator = FakeAuthenticator()
        authenticator.succeeds = false
        authenticator.passcodeMissing = true
        try await IntentLock.requireUnlocked(store: makeStore(enabled: true), authenticator: authenticator)
    }

    // MARK: Notifications

    @Test func notificationsKeepTheirTextWhileTheLockIsOff() {
        let content = LocalNotificationContent(identifier: "a", title: "Splt", body: "Sam added Dinner in Trip")
        #expect(NotificationPrivacy.apply(to: content, store: makeStore(enabled: false)) == content)
    }

    @Test func notificationsHideNamesAndAmountsWhileTheLockIsOn() {
        let content = LocalNotificationContent(identifier: "a", title: "Splt", body: "Sam added Dinner in Trip")
        let hidden = NotificationPrivacy.apply(to: content, store: makeStore(enabled: true))
        #expect(hidden.identifier == "a")
        #expect(hidden.body == NotificationPrivacy.genericBody)
        #expect(!hidden.body.contains("Sam"))

        let reminder = ReminderRequest(
            identifier: "r", title: "Pay Sam", body: "You owe Sam $40", fireDate: .now,
            link: URL(string: "splt://friend")!
        )
        let hiddenReminder = NotificationPrivacy.apply(to: reminder, store: makeStore(enabled: true))
        #expect(hiddenReminder.title == "Splt")
        #expect(hiddenReminder.body == NotificationPrivacy.genericBody)
        #expect(hiddenReminder.link == reminder.link)
    }
}
