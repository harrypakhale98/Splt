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
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focus: ExpenseFormField?
    @State private var keypadOpen: Bool
    @State private var sheet: FormSheet?
    @State private var fineTune: PersonSelection?
    @State private var confirmsDiscard = false
    @State private var confirmsDuplicate = false

    init(mode: ExpenseFormMode, services: DataServices) {
        let model = ExpenseFormModel(mode: mode, services: services)
        _model = State(initialValue: model)
        _keypadOpen = State(initialValue: !model.isEditing && model.total == nil)
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
                    content
                }
            }
            .background(Ink.paper.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationSubtitle(model.group?.name ?? "")
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
        .sheet(item: $sheet) { sheet in
            FormSheetContent(model: model, sheet: sheet) { self.sheet = nil }
                .presentationDetents(FormSheetContent.detents(for: sheet))
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $fineTune) { selection in
            FineTuneSheet(model: model, personID: selection.id) { fineTune = nil }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .haptics(.success, trigger: model.saveCount)
        .task(id: model.rateKey) { await model.refreshRate() }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !model.possibleDuplicates.isEmpty {
                    DuplicateBanner(model: model)
                }
                VStack(spacing: 8) {
                    AmountHero(model: model, keypadOpen: keypadOpen && !typeSize.isAccessibilitySize) {
                        Motion.perform(.snappy) { keypadOpen.toggle() }
                        focus = nil
                    }
                    TitleField(model: model, focus: $focus)
                    PaidByMenu(model: model) { keypadOpen = false }
                }
                WhoIsInSection(model: model) { keypadOpen = false }
                if model.split.method == .itemized {
                    ItemsTray(model: model) { sheet = .more }
                }
                SplitBarSection(model: model, onFineTune: { fineTune = PersonSelection(id: $0) }) {
                    keypadOpen = false
                    focus = nil
                }
                FormChipsRow(model: model) { opened in
                    keypadOpen = false
                    focus = nil
                    sheet = opened
                }
                .padding(.horizontal, -20)
                if case .add = model.mode {
                    DescribePill(model: model, focus: $focus)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: model.refreshKey) { model.refreshDuplicates() }
        .onChange(of: model.amountText) { model.refollowPayments() }
        .onChange(of: focus) { _, new in if new != nil { keypadOpen = false } }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 8) {
                if keypadOpen && !typeSize.isAccessibilitySize {
                    NumberPad(exponent: Currency.minorUnitExponent(for: model.currencyCode)) { key in
                        model.amountText = AmountKeypad.apply(
                            key, to: model.amountText, exponent: Currency.minorUnitExponent(for: model.currencyCode),
                            locale: model.locale
                        )
                    }
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                SaveBar(summary: model.summaryLine, hint: saveHint, canSave: model.canSave) {
                    if model.possibleDuplicates.isEmpty { save() } else { confirmsDuplicate = true }
                }
            }
            .padding(.top, 8)
            .background(Ink.paper)
            .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
        }
        .sheet(isPresented: Binding(
            get: { keypadOpen && typeSize.isAccessibilitySize }, set: { if !$0 { keypadOpen = false } }
        )) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text(AmountKeypad.display(model.amountText, locale: model.locale).isEmpty ? "0" : AmountKeypad.display(model.amountText, locale: model.locale))
                        .font(Typeface.hero(size: 48))
                        .monospacedDigit()
                    NumberPad(exponent: Currency.minorUnitExponent(for: model.currencyCode)) { key in
                        model.amountText = AmountKeypad.apply(
                            key, to: model.amountText, exponent: Currency.minorUnitExponent(for: model.currencyCode),
                            locale: model.locale
                        )
                    }
                }
                .padding(20)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done", role: .confirm) { keypadOpen = false } }
                }
            }
            .presentationDetents([.large])
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", role: .close) {
                if model.isDirty { confirmsDiscard = true } else { dismiss() }
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    /// What is wrong with the split, if anything. A missing amount or title needs no sentence.
    private var saveHint: String? {
        switch model.issue {
        case nil, .missingAmount?, .missingTitle?: nil
        default: model.blockingReason
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

/// The title, centered under the amount on a hairline, with the category suggestion when there is one.
private struct TitleField: View {
    @Bindable var model: ExpenseFormModel
    var focus: FocusState<ExpenseFormField?>.Binding
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            titleField
            if let suggestion = model.suggestedCategory, suggestion != model.category {
                Button {
                    model.acceptSuggestedCategory()
                } label: {
                    Label(suggestion.title, systemImage: suggestion.symbolName)
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(suggestion.title)")
                .accessibilityHint("Suggested category for this title")
            }
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }

    /// One line normally; at accessibility sizes it wraps so a long title never truncates.
    @ViewBuilder
    private var titleField: some View {
        let prompt = Text("What was it for?")
        let alignment: TextAlignment = model.suggestedCategory == nil && !typeSize.isAccessibilitySize ? .center : .leading
        if typeSize.isAccessibilitySize {
            TextField("Title", text: $model.title, prompt: prompt, axis: .vertical)
                .lineLimit(1...4)
                .font(.title3)
                .multilineTextAlignment(alignment)
                .focused(focus, equals: .title)
                .onChange(of: model.title) { model.titleDidChange() }
                .accessibilityIdentifier("expense-title")
        } else {
            TextField("Title", text: $model.title, prompt: prompt)
                .font(.title3)
                .multilineTextAlignment(alignment)
                .submitLabel(.done)
                .focused(focus, equals: .title)
                .onChange(of: model.title) { model.titleDidChange() }
                .accessibilityIdentifier("expense-title")
        }
    }
}

private struct DuplicateBanner: View {
    let model: ExpenseFormModel

    var body: some View {
        if let match = model.possibleDuplicates.first {
            Label {
                Text("\(match.title) for the same amount was added on \(match.date.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.footnote)
            } icon: {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Ink.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1) }
            .accessibilityElement(children: .combine)
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
