import Foundation
import SwiftUI
import Testing
@testable import Splt

private final class FakeAuthenticator: OwnerAuthenticating, @unchecked Sendable {
    var available = true
    var succeeds = true
    private(set) var attempts = 0

    func isAvailable() -> Bool { available }
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
}
