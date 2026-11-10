import SpltCore
import SwiftUI

/// The new group sheet. Brings its own navigation stack.
struct CreateGroupView: View {
    /// Called with the new group's id after it is saved, before the sheet closes.
    var onCreated: (GroupID) -> Void = { _ in }

    @Environment(\.dataServices) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let services {
                CreateGroupForm(services: services, onCreated: { id in
                    onCreated(id)
                    dismiss()
                })
            } else {
                EmptyStateView(
                    title: "Can't Create Groups",
                    systemImage: "exclamationmark.triangle",
                    description: "Splt couldn't open its storage."
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
            }
        }
    }
}

private struct CreateGroupForm: View {
    let onCreated: (GroupID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: CreateGroupViewModel
    @State private var newMemberName = ""
    @State private var showsContacts = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool
    @FocusState private var memberFocused: Bool

    init(services: DataServices, onCreated: @escaping (GroupID) -> Void) {
        self.onCreated = onCreated
        let currency = UserDefaults.standard.string(forKey: Preferences.Key.defaultCurrency)
            ?? Preferences.systemCurrencyCode
        _model = State(initialValue: CreateGroupViewModel(services: services, defaultCurrencyCode: currency))
    }

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                RaisedRows {
                    TextField("Group Name", text: $model.name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                    NavigationLink {
                        SymbolPickerView(selection: Binding(get: { model.symbol }, set: { model.chooseSymbol($0) }))
                    } label: {
                        HStack {
                            Text("Symbol")
                            Spacer()
                            Image(systemName: model.symbol)
                                .foregroundStyle(Ink.text)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .raisedSection()

            Section {
                RaisedRows {
                    Picker("Type", selection: Binding(get: { model.template }, set: { model.selectTemplate($0) })) {
                        ForEach(GroupTemplate.allCases) { template in
                            Label(template.title, systemImage: template.systemImage).tag(template)
                        }
                    }
                    if model.template == .trip {
                        DatePicker("Starts", selection: $model.tripStart, displayedComponents: .date)
                        DatePicker("Ends", selection: $model.tripEnd, in: model.tripStart..., displayedComponents: .date)
                    }
                    NavigationLink {
                        GroupCurrencyPickerView(selection: $model.currencyCode)
                    } label: {
                        LabeledContent("Currency", value: model.currencyCode)
                    }
                }
            }
            .raisedSection()

            membersSection

            Section {
                Toggle("Simplify Debts", isOn: $model.simplifiesDebts)
                    .raisedRow()
            } footer: {
                Text("Combines debts so the group settles with as few payments as possible.")
                    .padding(.horizontal, Depth.pageMargin + 4)
            }
            .raisedSection()
        }
        .paperBackground()
        .navigationTitle("New Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create", action: create)
                    .disabled(!model.canCreate)
            }
        }
        .onChange(of: model.name) { model.nameChanged() }
        .onChange(of: model.tripStart) { model.tripStartChanged() }
        .sheet(isPresented: $showsContacts) {
            ContactPicker { model.addContacts($0) }
                .ignoresSafeArea()
        }
        .alert("Couldn't Create Group", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { nameFocused = true }
    }

    private var membersSection: some View {
        Section {
            RaisedRows {
                HStack(spacing: 12) {
                    if let me = model.me {
                        AvatarView(person: me, size: 28)
                    } else {
                        AvatarView(name: String(localized: "You"), size: 28)
                    }
                    Text("You")
                }
                .accessibilityElement(children: .combine)
                ForEach(model.members) { member in
                    HStack(spacing: 12) {
                        AvatarView(name: member.name, size: 28)
                        VStack(alignment: .leading) {
                            Text(member.name)
                            if let hint = member.contactHint {
                                Text(hint)
                                    .font(.footnote)
                                    .foregroundStyle(Ink.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .swipeActions(edge: .trailing) {
                        Button("Remove", systemImage: "person.badge.minus", role: .destructive) {
                            if let index = model.members.firstIndex(where: { $0.id == member.id }) {
                                model.removeMembers(at: IndexSet(integer: index))
                            }
                        }
                    }
                }

                HStack {
                    TextField("Add by name", text: $newMemberName)
                        .focused($memberFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(addTypedMember)
                    Button("Add", systemImage: "plus.circle.fill", action: addTypedMember)
                        .labelStyle(.iconOnly)
                        .disabled(newMemberName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                NavigationLink {
                    FriendPickerView(
                        friends: model.friends, isSelected: { model.isSelected($0) }, toggle: { model.toggle($0) }
                    )
                } label: {
                    Label("Add from Friends", systemImage: "person.2")
                }
                Button("Add from Contacts", systemImage: "person.crop.circle.badge.plus") {
                    showsContacts = true
                }
            }
        } header: {
            SectionHeader("Members")
                .padding(.horizontal, Depth.pageMargin + 4)
        } footer: {
            Text("People who don't have Splt yet are added by name. They can join later.")
                .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func addTypedMember() {
        if model.addMember(named: newMemberName) {
            newMemberName = ""
            memberFocused = true
        }
    }

    private func create() {
        do {
            onCreated(try model.create())
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
        }
    }
}

#if DEBUG
#Preview {
    CreateGroupView()
        .environment(\.dataServices, SampleData.previewServices())
}
#endif
