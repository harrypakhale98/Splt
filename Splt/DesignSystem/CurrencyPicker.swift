import SwiftUI

/// The one currency list: search by name or code, tap to choose, and it closes.
/// Codes in `pinned` are listed first under `pinnedHeader` while the search is empty.
struct CurrencyPicker: View {
    @Binding var selection: String
    var title: LocalizedStringKey = "Currency"
    var pinned: [String] = []
    var pinnedHeader: LocalizedStringKey = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query = ""

    var body: some View {
        let matches = CurrencyCatalog.filter(CurrencyCatalog.cachedOptions(locale: locale), query: query)
        let top = query.isEmpty ? matches.filter { pinned.contains($0.code) } : []
        let rest = top.isEmpty ? matches : matches.filter { !top.contains($0) }

        List {
            if top.isEmpty {
                Section {
                    RaisedRows { ForEach(rest) { row($0) } }
                }
            } else {
                Section {
                    RaisedRows { ForEach(top) { row($0) } }
                } header: {
                    SectionHeader(pinnedHeader)
                }
                Section {
                    RaisedRows { ForEach(rest) { row($0) } }
                } header: {
                    SectionHeader("All currencies")
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .paperBackground()
        .overlay {
            if matches.isEmpty {
                EmptyStateView.search(query: query)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Currency or Code")
    }

    private func row(_ option: CurrencyOption) -> some View {
        Button {
            selection = option.code
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(option.name)
                        .foregroundStyle(Ink.text)
                    Text(option.code)
                        .font(.footnote)
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
}

#Preview {
    NavigationStack {
        CurrencyPicker(selection: .constant("EUR"), pinned: ["USD"], pinnedHeader: "Group currency")
    }
}
