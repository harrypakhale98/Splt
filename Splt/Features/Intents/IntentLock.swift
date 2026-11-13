import Foundation

/// Keeps Siri and Shortcuts from reading or changing Splt's data past the Face ID lock. They run
/// without the app's lock screen, so with the lock on they ask for Face ID themselves.
enum IntentLock {
    @MainActor
    static func requireUnlocked(
        store: UserDefaults = .standard, authenticator: any OwnerAuthenticating = BiometricAuth()
    ) async throws {
        guard store.bool(forKey: Preferences.Key.biometricLockEnabled) else { return }
        // a phone that lost its passcode drops the lock, as in the app, rather than strand its owner
        if authenticator.isPasscodeMissing() { return }
        guard await authenticator.authenticate(reason: String(localized: "Unlock Splt")) else {
            throw IntentError.locked
        }
    }
}
