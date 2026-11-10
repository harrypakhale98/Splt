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
                    TextField("Describe it", text: $model.describeText, prompt: example, axis: .vertical)
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
            if let unmatched {
                Label(unmatched, systemImage: "person.fill.questionmark")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
        }
        .onChange(of: focus.wrappedValue) { _, new in
            if new != nil, new != .describe { dictation.cancel() }
        }
        .onDisappear { dictation.cancel() }
    }

    /// An example built from the group's own people, so it shows how to name them.
    private var example: Text {
        let others = model.members.filter { $0.id != model.me?.id }.prefix(2)
        let names = others.compactMap { $0.name.split(separator: " ").first.map(String.init) }
        guard !names.isEmpty else { return Text("Dinner 60") }
        return Text("Dinner 60 with \(names.formatted(.list(type: .and)))")
    }

    /// The names the description used that aren't in the group, as one sentence.
    private var unmatched: String? {
        let names = model.unmatchedNames
        switch names.count {
        case 0: return nil
        case 1: return String(localized: "\(names[0]) isn't in this group, so they were left out.")
        default:
            return String(localized: "\(names.formatted(.list(type: .and))) aren't in this group, so they were left out.")
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
            HStack(spacing: 0) {
                if DictationController.isSupported {
                    Button(action: toggleDictation) {
                        Image(systemName: dictation.isListening ? "stop.circle.fill" : "mic")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
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
