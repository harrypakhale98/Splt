import SpltCore
import SwiftUI

/// Adds or edits an expense. Present it in a sheet; it brings its own navigation stack.
struct ExpenseFormView: View {
    let mode: ExpenseFormMode

    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            ExpenseFormScreen(mode: mode, services: services)
        } else {
            NavigationStack {
                EmptyStateView(
                    title: "Expenses Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: "Splt could not open its data. Restart the app and try again."
                )
                .navigationTitle("Expense")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct ExpenseFormScreen: View {
    @State private var model: ExpenseFormModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: ExpenseFormField?
    @State private var confirmsDiscard = false
    @State private var confirmsDuplicate = false

    init(mode: ExpenseFormMode, services: DataServices) {
        _model = State(initialValue: ExpenseFormModel(mode: mode, services: services))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.loadFailed {
                    EmptyStateView(
                        title: "Expense Not Found",
                        systemImage: "questionmark.circle",
                        description: "The group or expense may have been removed."
                    )
                } else {
                    form
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(model.isDirty)
        .confirmationDialog("Discard this expense?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .confirmationDialog("This looks like a duplicate", isPresented: $confirmsDuplicate, titleVisibility: .visible) {
            Button("Save Anyway") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(duplicateMessage)
        }
        .alert("Could Not Save", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.saveError ?? "")
        }
        .haptic(.success, trigger: model.saveCount)
        .task(id: model.rateKey) { await model.refreshRate() }
        .task {
            guard !model.isEditing, model.total == nil else { return }
            try? await Task.sleep(for: .milliseconds(350))
            focus = .amount
        }
    }

    private var form: some View {
        Form {
            if case .add = model.mode {
                DescribeSection(model: model)
            }
            if !model.possibleDuplicates.isEmpty {
                DuplicateWarningSection(model: model)
            }
            AmountSection(model: model, focus: $focus)
            DetailsSection(model: model, focus: $focus)
            PayerSection(model: model)
            SplitSection(model: model)
            if case .add = model.mode {
                RepeatSection(model: model)
            } else if model.isEditingRecurring {
                RepeatSection(model: model)
            }
            NotesSection(model: model)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: model.refreshKey) { model.refreshDuplicates() }
        .safeAreaBar(edge: .bottom) {
            StatusBar(text: model.statusText, isBlocking: model.blockingReason != nil)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button(focus == .amount ? "Next" : "Done") {
                focus = focus == .amount ? .title : nil
            }
        }
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", role: .close) {
                if model.isDirty { confirmsDiscard = true } else { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", role: .confirm) {
                if model.possibleDuplicates.isEmpty { save() } else { confirmsDuplicate = true }
            }
            .disabled(!model.canSave)
        }
    }

    private var navigationTitle: LocalizedStringKey {
        switch model.mode {
        case .add: "New Expense"
        case .edit: "Edit Expense"
        case .editRecurring: "Edit Recurring"
        }
    }

    private var duplicateMessage: String {
        guard let match = model.possibleDuplicates.first else { return "" }
        let date = match.date.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "\(match.title) for the same amount was added on \(date).")
    }

    private func save() {
        do {
            try model.save()
            dismiss()
        } catch {
            model.saveError = model.message(for: error)
        }
    }
}

private struct StatusBar: View {
    let text: String
    let isBlocking: Bool

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(isBlocking ? Color.orange : Color.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct DuplicateWarningSection: View {
    let model: ExpenseFormModel

    var body: some View {
        Section {
            ForEach(model.possibleDuplicates) { match in
                Label {
                    Text("\(match.title) for the same amount was added on \(match.date.formatted(date: .abbreviated, time: .omitted)).")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
            }
        } header: {
            Text("Possible Duplicate")
        }
    }
}

#if DEBUG
#Preview("New expense") {
    let scene = ExpensePreviewSupport.scene()
    ExpenseFormView(mode: .add(groupID: scene.trip.trip.id, prefill: nil))
        .environment(\.dataServices, scene.services)
}

#Preview("Prefilled") {
    let scene = ExpensePreviewSupport.scene()
    let draft = ExpenseDraft(title: "Taxi to Belem", total: Money(minorUnits: 1850, currencyCode: "EUR"), category: .transport)
    ExpenseFormView(mode: .add(groupID: scene.trip.trip.id, prefill: draft))
        .environment(\.dataServices, scene.services)
}

#Preview("Edit itemized") {
    let scene = ExpensePreviewSupport.scene()
    ExpenseFormView(mode: .edit(scene.expense("seafood")))
        .environment(\.dataServices, scene.services)
}

#Preview("Edit with several payers") {
    let scene = ExpensePreviewSupport.scene()
    ExpenseFormView(mode: .edit(scene.expense("beachbar")))
        .environment(\.dataServices, scene.services)
}

#Preview("Large text") {
    let scene = ExpensePreviewSupport.scene()
    ExpenseFormView(mode: .edit(scene.expense("groceries")))
        .environment(\.dataServices, scene.services)
        .dynamicTypeSize(.accessibility3)
}

#Preview("No data") {
    ExpenseFormView(mode: .add(groupID: GroupID(), prefill: nil))
}
#endif
