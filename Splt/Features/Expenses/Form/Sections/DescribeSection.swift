import PhotosUI
import SwiftUI

/// The "Describe it" field plus the buttons that fill the form from voice, a receipt scan or a photo.
struct DescribeSection: View {
    @Bindable var model: ExpenseFormModel
    @Environment(\.locale) private var locale
    @State private var dictation = DictationController()
    @FocusState private var focused: Bool

    var body: some View {
        Section {
            TextField(
                "Describe it", text: $model.describeText,
                prompt: Text("Dinner 60 with Sam and Priya, I paid"), axis: .vertical
            )
            .lineLimit(1...4)
            .submitLabel(.go)
            .focused($focused)
            .accessibilityIdentifier("expense-describe")
            .onSubmit(fill)
            .accessibilityHint("Type or say what you spent and who shared it, and the form fills itself in.")

            HStack {
                if DictationController.isSupported {
                    Button(action: toggleDictation) {
                        Label(
                            dictation.isListening ? "Stop" : "Dictate",
                            systemImage: dictation.isListening ? "stop.circle.fill" : "mic"
                        )
                    }
                }
                ReceiptActions(model: model)
                Spacer(minLength: 0)
                if model.isReading {
                    ProgressView()
                } else if !model.describeText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Fill In", action: fill)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .imageScale(.large)

            if let notice = model.filledNotice {
                Label(notice, systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !model.unmatchedNames.isEmpty {
                let names = model.unmatchedNames.formatted(.list(type: .and))
                Label("\(names) is not in this group, so they were left out.", systemImage: "person.fill.questionmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Quick Add")
        }
    }

    private func fill() {
        focused = false
        Task { await model.fillFromNote() }
    }

    private func toggleDictation() {
        dictation.toggle(
            locale: locale,
            update: { model.describeText = $0 },
            finished: { fill() }
        )
    }
}
