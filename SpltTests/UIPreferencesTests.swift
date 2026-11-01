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
