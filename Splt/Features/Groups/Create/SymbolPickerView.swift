import SwiftUI

/// A grid of group symbols.
struct SymbolPickerView: View {
    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 60), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(GroupSymbols.all, id: \.self) { symbol in
                    let isSelected = symbol == selection
                    Button {
                        selection = symbol
                        dismiss()
                    } label: {
                        Image(systemName: symbol)
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(isSelected ? Ink.paper : Ink.text)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: Depth.controlRadius, style: .continuous).fill(Ink.text)
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: Depth.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(GroupSymbols.label(for: symbol))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(12)
            // one card for the grid, rather than a hand-drawn box around every symbol
            .cardSurface()
            .padding(Depth.pageMargin)
        }
        .paperBackground()
        .navigationTitle("Symbol")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SymbolPickerView(selection: .constant("airplane")) }
}
