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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if reason != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                Text(reason ?? summary)
                    .foregroundStyle(reason == nil ? Color.legible : Color.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote.weight(.medium))
            .accessibilityElement(children: .combine)
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
        // it stays on screen, so at the largest sizes it must leave room for the form above it
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .background(.regularMaterial)
    }
}
