import SwiftUI

/// Typed access to the user's settings, backed by `@AppStorage`.
/// Declare it as a property of a view, or pass a different store in tests.
struct Preferences: DynamicProperty {
    enum Key {
        static let defaultCurrency = "preferences.defaultCurrency"
        static let hapticsEnabled = "preferences.hapticsEnabled"
        static let notificationsEnabled = "preferences.notificationsEnabled"
        static let onboardingCompleted = "preferences.onboardingCompleted"
    }

    @AppStorage var defaultCurrencyCode: String
    @AppStorage var hapticsEnabled: Bool
    @AppStorage var notificationsEnabled: Bool
    @AppStorage var onboardingCompleted: Bool

    init(store: UserDefaults = .standard) {
        _defaultCurrencyCode = AppStorage(wrappedValue: Self.systemCurrencyCode, Key.defaultCurrency, store: store)
        _hapticsEnabled = AppStorage(wrappedValue: true, Key.hapticsEnabled, store: store)
        _notificationsEnabled = AppStorage(wrappedValue: false, Key.notificationsEnabled, store: store)
        _onboardingCompleted = AppStorage(wrappedValue: false, Key.onboardingCompleted, store: store)
    }

    /// The currency of the phone's region, so a phone set to India starts in rupees and one set to
    /// Australia in Australian dollars. The app is English only, but iOS keeps the region, so this
    /// still works when the phone's language is one Splt doesn't offer.
    static var systemCurrencyCode: String {
        currencyCode(for: .current)
    }

    /// The currency for a locale's region, or US dollars when the locale has no region.
    static func currencyCode(for locale: Locale) -> String {
        locale.currency?.identifier ?? "USD"
    }
}
