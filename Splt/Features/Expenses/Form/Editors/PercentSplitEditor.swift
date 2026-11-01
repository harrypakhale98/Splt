import SwiftUI

struct PercentSplitEditor: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            ForEach(model.participantList) { person in
                HStack {
                    AvatarView(name: person.name, size: 28)
                    Text(model.displayName(for: person.id))
                    Spacer(minLength: 8)
                    TextField("Percent", text: Binding(
                        get: { model.split.percent[person.id, default: ""] },
                        set: { model.split.percent[person.id] = $0 }
                    ), prompt: Text("0"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 100)
                    .accessibilityLabel("Percent owed by \(model.displayName(for: person.id))")
                    Text("%").foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            if let remaining = model.percentRemaining {
                LabeledContent("Left to assign") {
                    if remaining == 0 {
                        Label("All assigned", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text(AmountInput.hundredthsText(remaining, locale: model.locale) + "%")
                            .monospacedDigit()
                            .foregroundStyle(remaining < 0 ? .red : .orange)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Button("Split Percentages Evenly") { model.fillPercentagesEvenly() }
        } header: {
            Text("Percentages")
        }
    }
}
