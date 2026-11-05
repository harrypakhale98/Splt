import SwiftUI

struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    private let preferences = Preferences()
    @State private var query = ""
    @State private var changeCount = 0

    var body: some View {
        let options = CurrencyCatalog.filter(CurrencyCatalog.options(locale: locale), query: query)

        List {
            ForEach(options) { option in
                Button {
                    preferences.defaultCurrencyCode = option.code
                    changeCount += 1
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(option.name)
                                .foregroundStyle(Ink.text)
                            Text(option.code)
                                .font(.subheadline)
                                .foregroundStyle(Ink.secondary)
                        }
                        Spacer()
                        if option.code == preferences.defaultCurrencyCode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Ink.text)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityAddTraits(option.code == preferences.defaultCurrencyCode ? .isSelected : [])
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .paperBackground()
        .overlay {
            if options.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Default Currency")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Currency or code")
        .haptic(.selection, trigger: changeCount)
    }
}

#Preview {
    NavigationStack { CurrencyPickerView() }
}
