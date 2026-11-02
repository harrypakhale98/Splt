import SpltCore
import SwiftUI
import UniformTypeIdentifiers

/// Imports a Splitwise CSV export as a new group. Push it, or present it with `SplitwiseImportSheet`.
struct SplitwiseImportView: View {
    /// Called with the new group. Without it the group opens in the Groups tab.
    var onImported: ((GroupID) -> Void)?

    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            SplitwiseImportContent(services: services, onImported: onImported)
        } else {
            EmptyStateView(
                title: "Can't Import",
                systemImage: "exclamationmark.triangle",
                description: "Splt couldn't open its storage."
            )
            .navigationTitle("Import from Splitwise")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The import flow in its own sheet, with a Cancel button.
struct SplitwiseImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack {
            SplitwiseImportView(onImported: { id in
                dismiss()
                router.open(.group(id.rawValue))
            })
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

private struct SplitwiseImportContent: View {
    let onImported: ((GroupID) -> Void)?

    @Environment(Router.self) private var router
    @State private var model: SplitwiseImportViewModel
    @State private var showsPicker = false
    @State private var importCount = 0

    init(services: DataServices, onImported: ((GroupID) -> Void)?) {
        self.onImported = onImported
        let currency = UserDefaults.standard.string(forKey: Preferences.Key.defaultCurrency)
            ?? Preferences.systemCurrencyCode
        _model = State(initialValue: SplitwiseImportViewModel(services: services, defaultCurrencyCode: currency))
    }

    var body: some View {
        Group {
            switch model.step {
            case .instructions:
                instructions
            case .preview:
                previewForm
            }
        }
        .navigationTitle("Import from Splitwise")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showsPicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.loadFile(at: url) }
            case .failure:
                model.errorMessage = String(localized: "Splt couldn't open that file. Choose a CSV exported from Splitwise.")
            }
        }
        .alert("Couldn't Import", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .haptic(.success, trigger: importCount)
    }

    // MARK: Instructions

    private var instructions: some View {
        List {
            Section {
                step(1, "Open your Splitwise account on the web.")
                step(2, "Choose Export.")
                step(3, "Pick CSV and save the file to Files.")
                step(4, "Come back here and choose the file.")
            } header: {
                Text("Export from Splitwise")
            } footer: {
                Text("Splt reads the file on this device. Nothing is uploaded, and your Splitwise group stays as it is.")
            }
            Section {
                Button("Choose CSV File", systemImage: "doc.badge.plus") {
                    showsPicker = true
                }
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.tint)
                .frame(minWidth: 20)
                .accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Preview

    @ViewBuilder
    private var previewForm: some View {
        @Bindable var model = model

        if let preview = model.preview {
            Form {
                if let existing = model.existingGroupID {
                    Section {
                        Label("You already imported this file.", systemImage: "checkmark.circle")
                        Button("Open Group") { open(existing) }
                    } footer: {
                        Text("Importing it again would add every expense twice, so it is turned off.")
                    }
                }

                Section("Group") {
                    TextField("Group Name", text: $model.groupName)
                        .textInputAutocapitalization(.words)
                    NavigationLink {
                        GroupCurrencyPickerView(selection: $model.currencyCode)
                    } label: {
                        LabeledContent("Currency", value: model.currencyCode)
                    }
                }

                Section("In the File") {
                    LabeledContent("Expenses") { Text(preview.expenseCount, format: .number).monospacedDigit() }
                    LabeledContent("Payments") { Text(preview.paymentCount, format: .number).monospacedDigit() }
                    ForEach(preview.totals, id: \.currencyCode) { total in
                        LabeledContent("Total Spent") { MoneyLabel(money: total) }
                    }
                }

                membersSection

                if !preview.warnings.isEmpty {
                    Section {
                        ForEach(preview.warnings, id: \.self) { warning in
                            Text("Line \(warning.line): \(warning.message)")
                                .font(.subheadline)
                        }
                    } header: {
                        Text("^[\(preview.warnings.count) row](inflect: true) skipped")
                    } footer: {
                        Text("These rows can't be imported. Everything else will be.")
                    }
                }

                Section {
                    Button("Choose Another File", systemImage: "arrow.uturn.backward") {
                        model.chooseAnotherFile()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: performImport)
                        .disabled(!model.canImport)
                }
            }
        }
    }

    private var membersSection: some View {
        Section {
            ForEach(model.mappings) { mapping in
                Picker(mapping.name, selection: Binding(
                    get: { model.choice(for: mapping.name) },
                    set: { model.setChoice($0, for: mapping.name) }
                )) {
                    Text("New Person").tag(MemberMapping.Choice.newPerson)
                    ForEach(model.candidates) { person in
                        Text(person.isMe ? String(localized: "\(person.name) (You)") : person.name)
                            .tag(MemberMapping.Choice.existing(person.id))
                    }
                }
            }
        } header: {
            Text("Match People")
        } footer: {
            if let problem = model.mappingProblem {
                Text(problem)
                    .foregroundStyle(.red)
            } else {
                Text("Match each Splitwise member to someone you already split with, or add them as a new person.")
            }
        }
    }

    // MARK: Actions

    private func performImport() {
        guard let id = model.performImport() else { return }
        importCount += 1
        open(id)
    }

    private func open(_ id: GroupID) {
        if let onImported {
            onImported(id)
        } else {
            router.open(.group(id.rawValue))
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

#if DEBUG
#Preview {
    NavigationStack { SplitwiseImportView() }
        .environment(Router())
        .environment(\.dataServices, SampleData.previewServices())
}
#endif
