import SwiftUI

/// What was recorded, with a way to take it back.
struct SettleDoneCard: View {
    let model: SettleModel
    let finished: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Ink.text)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : finished)
                .accessibilityHidden(true)
            Text("Payment Recorded")
                .font(Typeface.heading)
            if let receipt = model.receipt {
                Text(receipt.message)
                    .font(.body)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Undo") { model.undo() }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }
}
