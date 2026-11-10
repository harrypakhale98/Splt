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
    @Environment(Router.self) private var router: Router?

    var body: some View {
        if isPushed {
            content
        } else {
            NavigationStack { content }
                // set by the form below; cleared here because the form also disappears under a pushed picker
                .onDisappear { router?.hasUnsavedForm = false }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let services {
            GroupSettingsForm(groupID: groupID, services: services, onGroupRemoved: onGroupRemoved)
        } else {
            EmptyStateView.dataUnavailable
        }
    }
}

/// Members, archive and exports take effect as soon as they are tapped, so there is no Cancel to
/// suggest otherwise. Done saves the name, symbol, currency and trip fields.
private struct GroupSettingsForm: View {
    let onGroupRemoved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.groupSharing) private var sharing
    @Environment(\.locale) private var locale
    @Environment(Router.self) private var router: Router?
    @State private var model: GroupSettingsViewModel
    @State private var showsContacts = false
    @State private var showsDeleteConfirmation = false
    @State private var showsLeaveConfirmation = false
    @State private var newMemberName = ""

    init(groupID: GroupID, services: DataServices, onGroupRemoved: @escaping () -> Void) {
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
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: save)
                    .disabled(!model.canSave)
            }
        }
        // a swipe would drop a saveable edit, so only Done closes it then; an edit that can't be
        // saved (an empty name) can still be swiped away, so the sheet never traps you
        .interactiveDismissDisabled(model.hasFieldEdits && model.canSave)
        // a link waits for the same edits instead of closing the sheet over them
        .onChange(of: model.hasFieldEdits && model.canSave, initial: true) { _, unsaved in
            router?.hasUnsavedForm = unsaved
        }
        .onAppear { model.locale = locale }
        .task { await model.loadSharing(using: sharing) }
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
        .alert("Can't Leave", isPresented: leaveBlockedBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.leaveBlockedMessage ?? "")
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
                RaisedRows {
                    TextField("Group Name", text: $model.name)
                        .textInputAutocapitalization(.words)
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
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(GroupSymbols.spokenName(for: model.symbol))
                    NavigationLink {
                        GroupCurrencyPickerView(selection: $model.currencyCode)
                    } label: {
                        LabeledContent("Currency", value: model.currencyCode)
                    }
                }
            }
            .raisedSection()

            if model.isTrip {
                tripSection
            }

            membersSection

            if let group = model.group {
                GroupInviteSection(groupID: group.id, groupName: group.name)
            }

            exportSection

            Section {
                RaisedRows {
                    if model.group?.isArchived == true {
                        Button("Restore Group", systemImage: "tray.and.arrow.up") {
                            model.toggleArchived()
                        }
                    } else {
                        Button("Archive Group", systemImage: "archivebox") {
                            model.toggleArchived()
                        }
                    }
                    // you leave a group you joined and delete one of your own, never the other way round
                    if model.canLeave {
                        Button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            if let reason = model.leaveBlock {
                                model.leaveBlockedMessage = reason
                            } else {
                                showsLeaveConfirmation = true
                            }
                        }
                    }
                    if model.canDelete {
                        Button("Delete Group", systemImage: "trash", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .raisedSection()
        }
        .paperBackground()
        .onChange(of: model.tripStart) { model.tripStartChanged() }
    }

    private var tripSection: some View {
        @Bindable var model = model

        return Section {
            RaisedRows {
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
            }
        } header: {
            SectionHeader("Trip")
                .padding(.horizontal, Depth.pageMargin + 4)
        } footer: {
            if model.pinsRate {
                Text("Expenses in the other currency use this rate instead of the daily one.")
                    .padding(.horizontal, Depth.pageMargin + 4)
            }
        }
        .raisedSection()
    }

    private var membersSection: some View {
        Section {
            RaisedRows {
                ForEach(model.memberRows) { row in
                    HStack(spacing: 12) {
                        AvatarView(person: row.person, members: model.memberRows.map(\.person.id), size: 28)
                        VStack(alignment: .leading) {
                            Text(row.isMe ? String(localized: "You") : row.person.name)
                            if row.person.isPlaceholder {
                                Text("Not on Splt yet")
                                    .font(.subheadline)
                                    .foregroundStyle(Ink.secondary)
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
                    TextField("Add by Name", text: $newMemberName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(addTypedMember)
                    Button("Add", systemImage: "plus.circle.fill", action: addTypedMember)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Add Member")
                        .disabled(newMemberName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !model.friends.isEmpty {
                    // the same picker as New Group; each tap adds or removes the friend straight away
                    NavigationLink {
                        FriendPickerView(
                            friends: model.friends, isSelected: { model.isMember($0) }, toggle: { model.toggleFriend($0) }
                        )
                    } label: {
                        Label("Add from Friends", systemImage: "person.2")
                    }
                }
                Button("Add from Contacts", systemImage: "person.crop.circle.badge.plus") {
                    showsContacts = true
                }
            }
        } header: {
            SectionHeader("Members")
                .padding(.horizontal, Depth.pageMargin + 4)
        } footer: {
            Text("Someone can be removed once they are settled up.")
                .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()
    }

    private var exportSection: some View {
        Section {
            RaisedRows {
                GroupExportRow(state: { model.exportState($0) }) { kind in
                    Task { await model.prepareExport(kind) }
                }
            }
        }
        .raisedSection()
    }

    private var blockedBinding: Binding<Bool> {
        Binding(get: { model.blockedMessage != nil }, set: { if !$0 { model.blockedMessage = nil } })
    }

    private var leaveBlockedBinding: Binding<Bool> {
        Binding(get: { model.leaveBlockedMessage != nil }, set: { if !$0 { model.leaveBlockedMessage = nil } })
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
