import SwiftUI

/// The bottom of the screen: one line saying what will happen, and the Save button.
struct SaveBar: View {
    let summary: String
    let reason: String?
    let canSave: Bool
    var onSave: () -> Void

    @State private var tapped = 0

    var body: some View {
        VStack(spacing: 10) {
            Text(reason ?? summary)
                .font(.footnote.weight(.medium))
                .foregroundStyle(reason == nil ? Color.secondary : Color.orange)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("expense-summary")
            Button {
                tapped += 1
                onSave()
            } label: {
                Text("Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(PersonPalette.onColor)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!canSave)
            .accessibilityIdentifier("expense-save")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.regularMaterial)
    }
}
