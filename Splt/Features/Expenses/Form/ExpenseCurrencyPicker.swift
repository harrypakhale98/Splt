import SwiftUI

/// Chooses the currency of one expense. The group's currency is listed first.
struct ExpenseCurrencyPicker: View {
    @Binding var selection: String
    let groupCurrencyCode: String

    var body: some View {
        CurrencyPicker(selection: $selection, pinned: [groupCurrencyCode], pinnedHeader: "Group currency")
    }
}
