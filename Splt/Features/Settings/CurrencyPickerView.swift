import SwiftUI

/// Chooses the default currency for new groups and expenses, and saves it in Settings.
struct CurrencyPickerView: View {
    private let preferences = Preferences()

    var body: some View {
        CurrencyPicker(selection: preferences.$defaultCurrencyCode, title: "Default Currency")
            .haptic(.selection, trigger: preferences.defaultCurrencyCode)
    }
}

#Preview {
    NavigationStack { CurrencyPickerView() }
}
