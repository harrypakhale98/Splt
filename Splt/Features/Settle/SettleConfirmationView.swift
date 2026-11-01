import SwiftUI

/// A calm moment after a payment is recorded: a check mark settles into place.
struct SettleConfirmationView: View {
    let message: String
    let onUndo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var done = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 88))
                .foregroundStyle(done ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : done)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Payment Recorded")
                    .font(.title2.bold())
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Undo", action: onUndo)
                .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .haptic(.success, trigger: done)
        .task {
            if reduceMotion {
                done = true
            } else {
                withAnimation(.smooth(duration: 0.4)) { done = true }
            }
        }
    }
}

#Preview {
    SettleConfirmationView(message: "You paid Sam $12.50", onUndo: {})
}
