import SwiftUI

/// A grid of group symbols.
struct SymbolPickerView: View {
    @Binding var selection: String

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
                            .foregroundStyle(symbol == selection ? Ink.paper : Ink.text)
                            .background(
                                symbol == selection ? Ink.text : Color.clear,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.hairline)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                    .accessibilityAddTraits(symbol == selection ? .isSelected : [])
                }
            }
            .padding()
        }
        .background(Ink.paper.ignoresSafeArea())
        .navigationTitle("Symbol")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SymbolPickerView(selection: .constant("airplane")) }
}
