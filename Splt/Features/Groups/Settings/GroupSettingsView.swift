import SpltCore
import SwiftUI

/// Rename, change the symbol, currency and trip details, manage members, invite, export, leave or delete.
struct GroupSettingsView: View {
    let groupID: GroupID
    /// Called after the group is deleted or you leave it, so the screen behind can step back.
    var onGroupRemoved: () -> Void = {}
    /// True when shown inside a navigation stack as a pushed screen, which has its own back button.
    var isPushed = false

    @Environment(\.dataServices) private var services

    var body: some View {
        if isPushed {
            content
        } else {
            NavigationStack { content }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let services {
            GroupSettingsForm(
                groupID: groupID, services: services, showsCancel: !isPushed, onGroupRemoved: onGroupRemoved
            )
        } else {
            EmptyStateView(
                title: "Group Not Found",
                systemImage: "person.3",
                description: "Splt couldn't open its storage."
            )
        }
    }
}

private struct GroupSettingsForm: View {
    let showsCancel: Bool
    let onGroupRemoved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.groupSharing) private var sharing
    @Environment(\.locale) private var locale
    @State private var model: GroupSettingsViewModel
    @State private var showsContacts = false
    @State private var showsDeleteConfirmation = false
    @State private var showsLeaveConfirmation = false
    @State private var newMemberName = ""

    init(groupID: GroupID, services: DataServices, showsCancel: Bool, onGroupRemoved: @escaping () -> Void) {
        self.showsCancel = showsCancel
        self.onGroupRemoved = onGroupRemoved
        _model = State(initialValue: GroupSettingsViewModel(groupID: groupID, services: services))
    }

    var body: some View {
        @Bindable var model = model

        Group {
            if model.group != nil {
                form
            } else if model.didLoad {
                EmptyStateView(
                    title: "Group Not Found",
                    systemImage: "person.3",
                    description: "This group may have been deleted."
                )
            }
        }
        .navigationTitle("Group Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: save)
                    .disabled(!model.canSave)
            }
        }
        .onAppear { model.locale = locale }
        .sheet(isPresented: $showsContacts) {
            ContactPicker { drafts in
                for draft in drafts { model.addMember(named: draft.name, contactHint: draft.contactHint) }
            }
            .ignoresSafeArea()
        }
        .alert("Can't Remove", isPresented: blockedBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.blockedMessage ?? "")
        }
        .alert("Couldn't Finish", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("Delete Group?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Group", role: .destructive) {
                if model.delete() {
                    dismiss()
                    onGroupRemoved()
                }
            }
        } message: {
            Text("Every expense and payment in this group is removed for everyone. This can't be undone.")
        }
        .confirmationDialog("Leave Group?", isPresented: $showsLeaveConfirmation, titleVisibility: .visible) {
            Button("Leave Group", role: .destructive) {
                Task {
                    if await model.leave(using: sharing) {
                        dismiss()
                        onGroupRemoved()
                    }
                }
            }
        } message: {
            Text("You stop seeing this group. The others keep it.")
        }
    }

    private var form: some View {
        @Bindable var model = model

        return Form {
            Section {
                TextField("Group Name", text: $model.name)
                    .textInputAutocapitalization(.words)
                NavigationLink {
                    SymbolPickerView(
                        selection: Binding(get: { model.symbol }, set: { model.chooseSymbol($0) }),
                        color: model.group.map { GroupAppearance.color(for: $0.id) } ?? .accentColor
                    )
                } label: {
                    HStack {
                        Text("Symbol")
                        Spacer()
                        Image(systemName: model.symbol)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                NavigationLink {
                    GroupCurrencyPickerView(selection: $model.currencyCode)
                } label: {
                    LabeledContent("Currency", value: model.currencyCode)
                }
            }

            if model.isTrip {
                tripSection
            }

            membersSection

            if let group = model.group {
                GroupInviteSection(groupID: group.id, groupName: group.name)
            }

            exportSection

            Section {
                if model.group?.isArchived == true {
                    Button("Restore Group", systemImage: "tray.and.arrow.up") {
                        model.toggleArchived()
                    }
                } else {
                    Button("Archive Group", systemImage: "archivebox") {
                        model.toggleArchived()
                    }
                }
                Button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    if let reason = model.leaveBlock {
                        model.blockedMessage = reason
                    } else {
                        showsLeaveConfirmation = true
                    }
                }
                Button("Delete Group", systemImage: "trash", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            }
        }
        .onChange(of: model.tripStart) { model.tripStartChanged() }
    }

    private var tripSection: some View {
        @Bindable var model = model

        return Section {
            DatePicker("Starts", selection: $model.tripStart, displayedComponents: .date)
            DatePicker("Ends", selection: $model.tripEnd, in: model.tripStart..., displayedComponents: .date)
            Toggle("Pin Exchange Rate", isOn: $model.pinsRate)
            if model.pinsRate {
                NavigationLink {
                    GroupCurrencyPickerView(selection: $model.rateCurrencyCode)
                } label: {
                    LabeledContent("Other Currency", value: model.rateCurrencyCode)
                }
                LabeledContent("1 \(model.rateCurrencyCode) in \(model.currencyCode)") {
                    TextField("Rate", text: $model.rateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Trip")
        } footer: {
            if model.pinsRate {
                Text("Expenses in the other currency use this rate instead of the daily one.")
            }
        }
    }

    private var membersSection: some View {
        Section {
            ForEach(model.memberRows) { row in
                HStack(spacing: 12) {
                    AvatarView(name: row.person.name, size: 36)
                    VStack(alignment: .leading) {
                        Text(row.isMe ? String(localized: "You") : row.person.name)
                        if row.person.isPlaceholder {
                            Text("Hasn't joined yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .trailing) {
                    if !row.isMe {
                        Button("Remove", systemImage: "person.badge.minus", role: .destructive) {
                            model.remove(row)
                        }
                    }
                }
            }
            HStack {
                TextField("Add by name", text: $newMemberName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(addTypedMember)
                Button("Add", systemImage: "plus.circle.fill", action: addTypedMember)
                    .labelStyle(.iconOnly)
                    .disabled(newMemberName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !model.friendsToAdd.isEmpty {
                Menu {
                    ForEach(model.friendsToAdd) { friend in
                        Button(friend.name) { model.addMember(friend) }
                    }
                } label: {
                    Label("Add from Friends", systemImage: "person.2")
                }
            }
            Button("Add from Contacts", systemImage: "person.crop.circle.badge.plus") {
                showsContacts = true
            }
        } header: {
            Text("Members")
        } footer: {
            Text("Someone can be removed once they are settled up. Swipe a member to remove them.")
        }
    }

    private var exportSection: some View {
        Section("Export") {
            ForEach(GroupExportKind.allCases) { kind in
                GroupExportRow(kind: kind, state: model.exportState(kind)) {
                    Task { await model.prepareExport(kind) }
                }
            }
        }
    }

    private var blockedBinding: Binding<Bool> {
        Binding(get: { model.blockedMessage != nil }, set: { if !$0 { model.blockedMessage = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private func addTypedMember() {
        model.addMember(named: newMemberName)
        newMemberName = ""
    }

    private func save() {
        do {
            try model.save()
            dismiss()
        } catch {
            model.errorMessage = GroupErrorMessage.text(for: error)
        }
    }
}

#if DEBUG
#Preview {
    let services = SampleData.previewServices()
    let trip = (try? services.groups.groups(includeArchived: false).first { $0.kind == .trip }) ?? nil
    if let trip {
        GroupSettingsView(groupID: trip.id)
            .environment(\.dataServices, services)
    }
}
#endif
