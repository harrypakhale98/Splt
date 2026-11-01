import SwiftUI

struct AdjustmentSplitEditor: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            ForEach(model.participantList) { person in
                HStack {
                    AvatarView(name: person.name, size: 28)
                    Text(model.displayName(for: person.id))
                    Spacer(minLength: 8)
                    TextField("Adjustment", text: Binding(
                        get: { model.split.adjustments[person.id, default: ""] },
                        set: { model.split.adjustments[person.id] = $0 }
                    ), prompt: Text("0"))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 140)
                    .accessibilityLabel("Adjustment for \(model.displayName(for: person.id))")
                }
            }
        } header: {
            Text("Adjustments")
        } footer: {
            Text("Enter an amount to add to someone's share, or a minus amount to take off. Everything else is split equally.")
        }
    }
}
