import SwiftUI

/// Picks a currency code for a group. Unlike the Settings picker it does not touch the default currency.
struct GroupCurrencyPickerView: View {
    @Binding var selection: String

    var body: some View {
        CurrencyPicker(selection: $selection)
    }
}

#Preview {
    NavigationStack { GroupCurrencyPickerView(selection: .constant("EUR")) }
}
