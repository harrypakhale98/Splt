import SwiftUI

/// Picks a currency code for a group. Unlike the Settings picker it does not touch the default currency.
struct GroupCurrencyPickerView: View {
    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""

    var body: some View {
        let options = CurrencyCatalog.filter(CurrencyCatalog.options(locale: locale), query: query)

        List(options) { option in
            Button {
                selection = option.code
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(option.name)
                            .foregroundStyle(.primary)
                        Text(option.code)
                            .font(.subheadline)
                            .foregroundStyle(Ink.secondary)
                    }
                    Spacer()
                    if option.code == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Ink.text)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityAddTraits(option.code == selection ? .isSelected : [])
        }
        .paperBackground()
        .overlay {
            if options.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Currency or code")
    }
}

#Preview {
    NavigationStack { GroupCurrencyPickerView(selection: .constant("EUR")) }
}
