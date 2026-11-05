import SwiftUI

/// Chooses the currency of one expense. The group's currency is listed first.
struct ExpenseCurrencyPicker: View {
    @Binding var selection: String
    let groupCurrencyCode: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""

    var body: some View {
        let all = CurrencyCatalog.options(locale: locale)
        let matches = CurrencyCatalog.filter(all, query: query)
        let pinned = query.isEmpty ? matches.filter { $0.code == groupCurrencyCode } : []
        let rest = matches.filter { !pinned.contains($0) }

        List {
            if !pinned.isEmpty {
                Section(header: Text("Group Currency").foregroundStyle(Ink.secondary)) {
                    ForEach(pinned) { row($0) }
                }
            }
            Section(pinned.isEmpty ? "" : "All Currencies") {
                ForEach(rest) { row($0) }
            }
        }
        .paperBackground()
        .overlay {
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Currency or code")
    }

    private func row(_ option: CurrencyOption) -> some View {
        Button {
            selection = option.code
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(option.name).foregroundStyle(.primary)
                    Text(option.code).font(.subheadline).foregroundStyle(Ink.secondary)
                }
                Spacer()
                if option.code == selection {
                    Image(systemName: "checkmark").foregroundStyle(Ink.text).accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(option.code == selection ? .isSelected : [])
    }
}
