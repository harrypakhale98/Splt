import SwiftUI

/// The bottom of the screen: the Save button, with a line above it only when something in the split needs fixing.
struct SaveBar: View {
    let summary: String
    let hint: String?
    let canSave: Bool
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("expense-summary")
            }
            Button(action: onSave) {
                Text("Save")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSave)
            .accessibilityHint(summary)
            .accessibilityIdentifier("expense-save")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Ink.paper)
    }
}
