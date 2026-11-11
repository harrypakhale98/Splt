import PhotosUI
import SpltCore
import SwiftUI

/// Rename, change the cover photo, symbol, currency and trip details, manage members, invite, export, leave or delete.
struct GroupSettingsView: View {
    let groupID: GroupID
    /// Called after the group is deleted or you leave it, so the screen behind can step back.
    var onGroupRemoved: () -> Void = {}

    @Environment(\.dataServices) private var services
    @Environment(Router.self) private var router: Router?

    var body: some View {
        NavigationStack { content }
            // set by the form below; cleared here because the form also disappears under a pushed picker
            .onDisappear { router?.hasUnsavedForm = false }
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

/// The cover photo, members, archive and exports take effect as soon as they are tapped, so there is no
/// Cancel to suggest otherwise. Done saves the name, symbol, currency, trip fields and default split.
private struct GroupSettingsForm: View {
    let onGroupRemoved: () -> Void

    /// Invites go through iCloud, so without it there is nothing to send. The sample trip shows them anyway.
    private var canInvite: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampledata") { return true }
        #endif
        return SyncRuntime.shared.status.isConnected
    }

    /// A member, and for someone added by name, an Invite that sends a link made for them.
    @ViewBuilder
    private func memberRow(_ row: GroupSettingsViewModel.MemberRow) -> some View {
        let label = HStack(spacing: 12) {
            AvatarView(person: row.person, members: model.memberRows.map(\.person.id), size: 28)
            VStack(alignment: .leading) {
                Text(row.isMe ? String(localized: "You") : row.person.name)
                    .foregroundStyle(Ink.text)
                if row.person.isPlaceholder {
                    Text("Not on Splt yet")
                        .font(.subheadline)
                        .foregroundStyle(Ink.secondary)
                }
            }
        }
        if row.person.isPlaceholder, canInvite {
            Button {
                invitee = .person(row.person)
            } label: {
                HStack {
                    label
                    Spacer()
                    Text("Invite")
                        .foregroundStyle(Ink.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.tertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Sends \(row.person.name) a link made for them")
            .accessibilityIdentifier("member.invite")
        } else {
            label
                .accessibilityElement(children: .combine)
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.groupSharing) private var sharing
    @Environment(\.locale) private var locale
    @Environment(Router.self) private var router: Router?
    @State private var model: GroupSettingsViewModel
    @State private var showsContacts = false
    @State private var showsDeleteConfirmation = false
    @State private var showsLeaveConfirmation = false
    @State private var newMemberName = ""
    @State private var showsPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showsCamera = false
    /// Who is being sent an invite: one person added by name, or everyone still waiting.
    @State private var invitee: Invitee?
    private let services: DataServices

    init(groupID: GroupID, services: DataServices, onGroupRemoved: @escaping () -> Void) {
        self.onGroupRemoved = onGroupRemoved
        self.services = services
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
        .sheet(item: $invitee) { invitee in
            InvitePersonSheet(groupID: model.groupID, invitee: invitee, services: services)
        }
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
                    if model.canHaveCover {
                        coverRow
                    }
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
            } footer: {
                if model.canHaveCover {
                    Text("The photo shows on the group and in your list of groups. Without a photo, the symbol shows.")
                        .padding(.horizontal, Depth.pageMargin + 4)
                }
            }
            .raisedSection()

            if model.isTrip {
                tripSection
            }

            membersSection

            defaultSplitSection

            if let group = model.group {
                GroupInviteSection(
                    groupID: group.id, groupName: group.name, isSharedWithMe: model.isSharedWithMe == true,
                    // one link for the group chat is worth it once two or more people are still waiting
                    inviteEveryone: canInvite && model.memberRows.filter(\.person.isPlaceholder).count >= 2
                        ? { invitee = .everyone } : nil
                )
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
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.setCover(data)
                } else {
                    model.errorMessage = String(localized: "That photo could not be loaded.")
                }
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(
                onFinish: { data in
                    showsCamera = false
                    Task { await model.setCover(data) }
                },
                onCancel: { showsCamera = false }
            )
            .ignoresSafeArea()
        }
    }

    /// Opens a menu to pick, take or remove the photo. Shows the photo itself, or Add without one.
    private var coverRow: some View {
        Menu {
            Button("Choose from Photos", systemImage: "photo") { showsPhotoPicker = true }
            if CameraPicker.isSupported {
                Button("Take Photo", systemImage: "camera") { showsCamera = true }
            }
            if model.coverFileName != nil {
                Divider()
                Button("Remove Photo", systemImage: "trash", role: .destructive) { model.removeCover() }
            }
        } label: {
            HStack {
                Text("Cover Photo")
                    .foregroundStyle(Ink.text)
                Spacer()
                if model.isChangingCover {
                    ProgressView()
                } else if let cover = model.coverFileName {
                    // until the photo arrives from another phone, a plain photo mark stands in
                    CoverThumbnail(fileName: cover, store: .covers, side: 32) {
                        Image(systemName: "photo").foregroundStyle(Ink.secondary)
                    }
                } else {
                    Text("Add")
                        .foregroundStyle(Ink.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .disabled(model.isChangingCover)
        .accessibilityLabel("Cover Photo")
        .accessibilityValue(model.coverFileName == nil ? String(localized: "None") : String(localized: "Photo"))
    }

    private var defaultSplitSection: some View {
        @Bindable var model = model

        return Section {
            RaisedRows {
                NavigationLink {
                    DefaultSplitEditor(draft: $model.splitDraft, people: model.memberRows.map(\.person), me: model.myRow?.person.id)
                } label: {
                    LabeledContent("Default Split", value: model.splitDraft.method.title)
                }
            }
        } footer: {
            Text("New expenses in this group start with this split.")
                .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()
    }

    private var tripSection: some View {
        @Bindable var model = model

        return Section {
            RaisedRows {
                DatePicker("Starts", selection: $model.tripStart, displayedComponents: .date)
                DatePicker("Ends", selection: $model.tripEnd, in: model.tripStart..., displayedComponents: .date)
                Toggle("Pin Exchange Rate", isOn: $model.pinsRate)
                    .tint(Ink.switchOn)
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
                    memberRow(row)
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
                    // the same picker as New Group. A tap adds the friend straight away. Someone already in
                    // the group is ticked and can't be tapped, because removing is a swipe on the member list.
                    NavigationLink {
                        FriendPickerView(
                            friends: model.friends, isSelected: { model.isMember($0) }, toggle: { model.addFriend($0) },
                            canToggle: { !model.isMember($0) }
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
