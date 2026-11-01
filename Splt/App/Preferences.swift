import SwiftUI

/// Typed access to the user's settings, backed by `@AppStorage`.
/// Declare it as a property of a view, or pass a different store in tests.
struct Preferences: DynamicProperty {
    enum Key {
        static let defaultCurrency = "preferences.defaultCurrency"
        static let hapticsEnabled = "preferences.hapticsEnabled"
        static let notificationsEnabled = "preferences.notificationsEnabled"
    }

    @AppStorage var defaultCurrencyCode: String
    @AppStorage var hapticsEnabled: Bool
    @AppStorage var notificationsEnabled: Bool

    init(store: UserDefaults = .standard) {
        _defaultCurrencyCode = AppStorage(wrappedValue: Self.systemCurrencyCode, Key.defaultCurrency, store: store)
        _hapticsEnabled = AppStorage(wrappedValue: true, Key.hapticsEnabled, store: store)
        _notificationsEnabled = AppStorage(wrappedValue: false, Key.notificationsEnabled, store: store)
    }

    static var systemCurrencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }
}
