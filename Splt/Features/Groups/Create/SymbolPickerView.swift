import SwiftUI

/// A grid of group symbols.
struct SymbolPickerView: View {
    @Binding var selection: String
    let color: Color

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 60), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(GroupSymbols.all, id: \.self) { symbol in
                    Button {
                        selection = symbol
                        dismiss()
                    } label: {
                        Image(systemName: symbol)
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(symbol == selection ? Color.white : color)
                            .background(
                                symbol == selection ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.12)),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(GroupSymbols.spokenName(for: symbol))
                    .accessibilityAddTraits(symbol == selection ? .isSelected : [])
                }
            }
            .padding()
        }
        .navigationTitle("Symbol")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SymbolPickerView(selection: .constant("airplane"), color: .blue) }
}
