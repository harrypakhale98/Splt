import SwiftUI

/// The "Describe it" line: type or dictate what you spent, and the form fills itself in.
struct DescribePill: View {
    @Bindable var model: ExpenseFormModel
    var focus: FocusState<ExpenseFormField?>.Binding

    @Environment(\.locale) private var locale
    @State private var dictation = DictationController()

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField(
                        "Describe it", text: $model.describeText,
                        prompt: Text("Dinner 60 with Sam and Priya"), axis: .vertical
                    )
                    .lineLimit(1...3)
                    .submitLabel(.go)
                    .focused(focus, equals: .describe)
                    .onSubmit(fill)
                    .accessibilityIdentifier("expense-describe")
                    .accessibilityHint("Type or say what you spent and who shared it, and the form fills itself in.")

                    trailing
                }
                .frame(minHeight: 44)
                Rectangle().fill(Ink.hairline).frame(height: 1)
            }

            if let notice = model.filledNotice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
            if !model.unmatchedNames.isEmpty {
                let names = model.unmatchedNames.formatted(.list(type: .and))
                Label("\(names) is not in this group, so they were left out.", systemImage: "person.fill.questionmark")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if model.isReading {
            ProgressView()
        } else if !model.describeText.trimmingCharacters(in: .whitespaces).isEmpty {
            Button("Fill In", action: fill)
                .font(.body.weight(.medium))
                .frame(minHeight: 44)
        } else {
            HStack(spacing: 14) {
                if DictationController.isSupported {
                    Button(action: toggleDictation) {
                        Image(systemName: dictation.isListening ? "stop.circle.fill" : "mic")
                    }
                    .accessibilityLabel(dictation.isListening ? "Stop dictating" : "Dictate")
                }
                ReceiptActions(model: model)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Ink.secondary)
        }
    }

    private func fill() {
        focus.wrappedValue = nil
        Task { await model.fillFromNote() }
    }

    private func toggleDictation() {
        dictation.toggle(locale: locale, update: { model.describeText = $0 }, finished: { fill() })
    }
}
