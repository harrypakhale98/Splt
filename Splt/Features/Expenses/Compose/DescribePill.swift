import SwiftUI

/// The "Describe it" glass pill: type or dictate what you spent, and the form fills itself in.
struct DescribePill: View {
    @Bindable var model: ExpenseFormModel
    var focus: FocusState<ExpenseFormField?>.Binding

    @Environment(\.locale) private var locale
    @State private var dictation = DictationController()

    var body: some View {
        VStack(spacing: 8) {
            GlassPill(isInteractive: true) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
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
            }

            if let notice = model.filledNotice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.legible)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
            if !model.unmatchedNames.isEmpty {
                let names = model.unmatchedNames.formatted(.list(type: .and))
                Label(
                    model.unmatchedNames.count == 1
                        ? "\(names) is not in this group, so they were left out."
                        : "\(names) are not in this group, so they were left out.",
                    systemImage: "person.fill.questionmark"
                )
                .font(.footnote)
                .foregroundStyle(.legible)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
            }
            if !model.ambiguousNames.isEmpty {
                let names = model.ambiguousNames.formatted(.list(type: .and))
                Label("More than one person here is called \(names). Choose who you mean below.", systemImage: "person.2.fill")
                    .font(.footnote)
                    .foregroundStyle(.legible)
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
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
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
            .imageScale(.large)
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
