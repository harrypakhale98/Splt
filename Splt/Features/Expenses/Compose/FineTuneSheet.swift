import SpltCore
import SwiftUI

/// Tap a segment of the bar to nudge that person's share one step at a time.
struct FineTuneSheet: View {
    let model: ExpenseFormModel
    let personID: PersonID
    var onDone: () -> Void

    @Environment(\.locale) private var locale
    @State private var steps = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let segment = model.barData?.segments.first(where: { $0.id == personID }), let data = model.barData {
                    AvatarView(name: segment.person.name, id: segment.id, members: model.members.map(\.id), size: 72)
                    Text(model.displayName(for: segment.id)).font(.title3.weight(.semibold))
                    if let amount = segment.amount {
                        HeroAmount(amount, showsSign: false)
                    }
                    Text(percentText(segment, scale: data.scale))
                        .font(.headline)
                        .foregroundStyle(.legible)
                        .monospacedDigit()

                    if data.canDrag {
                        HStack(spacing: 28) {
                            stepButton(systemImage: "minus", label: "Less", increase: false)
                            stepButton(systemImage: "plus", label: "More", increase: true)
                        }
                        Text("\(model.barStepDescription) per tap. The difference comes from or goes to the next person.")
                            .font(.footnote)
                            .foregroundStyle(.legible)
                            .multilineTextAlignment(.center)
                    }
                    if model.split.method != .itemized {
                        Button("Take \(model.displayName(for: segment.id)) Out of the Split", role: .destructive) {
                            model.toggleParticipant(segment.id)
                            onDone()
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Fine Tune")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", role: .confirm, action: onDone) }
            }
            .haptics(.tick, trigger: steps)
        }
    }

    private func stepButton(systemImage: String, label: LocalizedStringKey, increase: Bool) -> some View {
        Button {
            if model.adjustShare(of: personID, increase: increase) { steps += 1 }
        } label: {
            Image(systemName: systemImage)
                .font(.title.weight(.semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    private func percentText(_ segment: SplitBarSegment, scale: Int64) -> String {
        guard scale > 0 else { return "" }
        let percent = Double(segment.weight) / Double(scale) * 100
        return (percent / 100).formatted(.percent.locale(locale).precision(.fractionLength(0...1)))
    }
}
