import SpltCore
import SwiftUI

/// Adds or edits an expense. Present it in a sheet; it brings its own navigation stack.
struct ExpenseFormView: View {
    let mode: ExpenseFormMode
    /// Told about the saved expense, as when a payment from To Split becomes one.
    var onSaved: (@MainActor (Expense) -> Void)?

    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            ExpenseFormScreen(mode: mode, services: services, onSaved: onSaved)
        } else {
            NavigationStack {
                EmptyStateView.dataUnavailable
                    .navigationTitle("Expense")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct ExpenseFormScreen: View {
    @Environment(Router.self) private var router: Router?
    @State private var model: ExpenseFormModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @FocusState private var focus: ExpenseFormField?
    @State private var keypadOpen: Bool
    @State private var formHeight: CGFloat = 0
    @State private var sheet: FormSheet?
    @State private var fineTune: PersonSelection?
    @State private var confirmsDiscard = false
    @State private var confirmsDuplicate = false
    private let onSaved: (@MainActor (Expense) -> Void)?

    init(mode: ExpenseFormMode, services: DataServices, onSaved: (@MainActor (Expense) -> Void)? = nil) {
        self.onSaved = onSaved
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
            // the group line under the amount names it when it can be changed
            .navigationSubtitle(model.switchableGroups.isEmpty ? (model.group?.name ?? "") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(model.isDirty)
        .onChange(of: model.isDirty, initial: true) { router?.hasUnsavedForm = model.isDirty }
        .onDisappear { router?.hasUnsavedForm = false }
        .confirmationDialog("Discard Expense?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .confirmationDialog("Possible Duplicate", isPresented: $confirmsDuplicate, titleVisibility: .visible) {
            Button("Save Anyway") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(duplicateMessage)
        }
        .alert("Couldn't Save", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
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
                // on a short screen the medium height ends above the plus and minus buttons
                .presentationDetents(formHeight < 700 ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .haptics(.success, trigger: model.saveCount)
        .task(id: model.rateKey) { await model.refreshRate() }
    }

    // MARK: Content

    /// Where an inline number pad would leave no room for the form: the largest text sizes and landscape.
    private var keypadUsesSheet: Bool {
        typeSize.isAccessibilitySize || verticalSizeClass == .compact
    }

    /// The pad shares the screen with the form, and its promise is that it never covers the split.
    /// So while it is up, on a screen where both do not fit as they are, the sections sit closer
    /// and the keys are a little lower.
    private var padIsInline: Bool { keypadOpen && !keypadUsesSheet }
    private var isSnug: Bool { formHeight < 840 }
    private var isPacked: Bool { padIsInline && isSnug }

    private var content: some View {
        ScrollView {
            VStack(spacing: isPacked ? 12 : 24) {
                if !model.possibleDuplicates.isEmpty {
                    DuplicateBanner(model: model)
                }
                if model.split.method != .itemized, let notice = model.scanNotice {
                    Label(notice, systemImage: "doc.text.viewfinder")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: 8) {
                    AmountHero(model: model, keypadOpen: keypadOpen && !keypadUsesSheet) {
                        Motion.perform(Motion.settle) { keypadOpen.toggle() }
                        focus = nil
                    }
                    TitleField(model: model, focus: $focus)
                    GroupAndPayerLine(model: model) { closeKeypad() }
                }
                WhoIsInSection(model: model) { closeKeypad() }
                if model.split.method == .itemized {
                    ItemsTray(model: model) {
                        closeKeypad()
                        focus = nil
                        sheet = .items
                    }
                }
                SplitBarSection(model: model, onFineTune: { fineTune = PersonSelection(id: $0) }) {
                    closeKeypad()
                    focus = nil
                }
                FormChipsRow(model: model) { opened in
                    closeKeypad()
                    focus = nil
                    sheet = opened
                }
                .padding(.horizontal, -20)
                if case .add = model.mode {
                    DescribePill(model: model, focus: $focus)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, isPacked ? 0 : 8)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { formHeight = $0 }
        .onChange(of: model.refreshKey) { model.refreshDuplicates() }
        .onChange(of: model.amountText) { model.refollowPayments() }
        .onChange(of: focus) { _, new in if new != nil { closeKeypad() } }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 8) {
                if padIsInline {
                    NumberPad(exponent: Currency.minorUnitExponent(for: model.currencyCode), compact: isSnug) { key in
                        model.amountText = AmountKeypad.apply(
                            key, to: model.amountText, exponent: Currency.minorUnitExponent(for: model.currencyCode),
                            locale: model.locale
                        )
                    }
                    .padding(.horizontal, 20)
                    .motionTransition(.move(edge: .bottom).combined(with: .opacity))
                }
                // at the largest sizes and in landscape the keyboard and this bar would leave almost nothing of the field being typed in
                if focus == nil || !keypadUsesSheet {
                    SaveBar(summary: model.summaryLine, hint: saveHint, canSave: model.canSave) {
                        if model.possibleDuplicates.isEmpty { save() } else { confirmsDuplicate = true }
                    }
                }
            }
            .padding(.top, isPacked ? 4 : 8)
            .background(Ink.paper)
            .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
        }
        .sheet(isPresented: Binding(
            get: { keypadOpen && keypadUsesSheet }, set: { if !$0 { keypadOpen = false } }
        )) {
            NavigationStack {
                // in landscape the amount sits beside the pad, as four rows of keys and the amount do not fit on top of each other
                (verticalSizeClass == .compact ? AnyLayout(HStackLayout(spacing: 20)) : AnyLayout(VStackLayout(spacing: 16))) {
                    Text(AmountKeypad.display(model.signedAmountText, locale: model.locale).isEmpty ? "0" : AmountKeypad.display(model.signedAmountText, locale: model.locale))
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
            Button("Cancel", role: .cancel) {
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

    /// Lowers the number pad with the same motion that raised it, so the save bar slides rather than jumps.
    private func closeKeypad() {
        guard keypadOpen else { return }
        Motion.perform(Motion.settle) { keypadOpen = false }
    }

    private func save() {
        do {
            let saved = try model.save()
            onSaved?(saved)
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
                .onChange(of: model.title) {
                    // this field wraps, so Return arrives as a line break: treat it as finishing the title
                    if model.title.contains(where: \.isNewline) {
                        model.title = model.title.split(whereSeparator: \.isNewline).joined(separator: " ")
                        focus.wrappedValue = nil
                    }
                    model.titleDidChange()
                }
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
