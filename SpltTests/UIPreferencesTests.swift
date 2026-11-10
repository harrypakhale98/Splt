import Foundation
import Testing
@testable import Splt

@MainActor
@Suite("Preferences")
struct UIPreferencesTests {
    private func makeStore() -> UserDefaults {
        let suite = "splt.tests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        return store
    }

    @Test func defaults() {
        let preferences = Preferences(store: makeStore())
        #expect(preferences.hapticsEnabled)
        #expect(!preferences.notificationsEnabled)
        #expect(preferences.defaultCurrencyCode == Preferences.systemCurrencyCode)
    }

    @Test(arguments: [
        ("en_IN", "INR"), ("en_AU", "AUD"), ("en_CA", "CAD"), ("en_GB", "GBP"), ("en_US", "USD"),
        ("en_DE", "EUR"), ("en_JP", "JPY"), ("en_AE", "AED"), ("en_SG", "SGD"), ("en_BR", "BRL"),
        // the app is English only, so a phone set to Hindi in India reads as English (India)
        ("hi_IN", "INR"), ("fr_CA", "CAD"),
    ])
    func theDefaultCurrencyFollowsThePhonesRegion(identifier: String, currency: String) {
        #expect(Preferences.currencyCode(for: Locale(identifier: identifier)) == currency)
    }

    @Test func aLocaleWithoutARegionFallsBackToDollars() {
        #expect(Preferences.currencyCode(for: Locale(identifier: "en")) == "USD")
    }

    @Test func valuesPersistAcrossInstances() {
        let store = makeStore()
        let first = Preferences(store: store)
        first.defaultCurrencyCode = "EUR"
        first.hapticsEnabled = false
        first.notificationsEnabled = true

        let second = Preferences(store: store)
        #expect(second.defaultCurrencyCode == "EUR")
        #expect(!second.hapticsEnabled)
        #expect(second.notificationsEnabled)
    }

    @Test func writesUseStableKeys() {
        let store = makeStore()
        Preferences(store: store).defaultCurrencyCode = "JPY"
        #expect(store.string(forKey: Preferences.Key.defaultCurrency) == "JPY")
    }

    @Test func storesAreIndependent() {
        let a = Preferences(store: makeStore())
        let b = Preferences(store: makeStore())
        a.hapticsEnabled = false
        #expect(b.hapticsEnabled)
    }
}
