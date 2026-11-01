import SpltCore
import SwiftUI

/// The New Friend sheet: add by name, pick from Contacts, or share and scan invites.
struct AddFriendView: View {
    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            AddFriendContent(services: services)
        } else {
            NavigationStack {
                EmptyStateView(
                    title: "Can't Add Friends",
                    systemImage: "exclamationmark.triangle",
                    description: "Splt couldn't open its storage."
                )
            }
        }
    }
}

private struct AddFriendContent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    @State private var model: AddFriendModel
    @State private var showsContacts = false
    @State private var showsScanner = false
    @State private var scanMessage: String?
    @State private var addedCount = 0
    @FocusState private var nameFocused: Bool

    init(services: DataServices) {
        _model = State(initialValue: AddFriendModel(services: services))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let invite = router.pendingInvite {
                    invitationSection(invite)
                }
                nameSection
                contactsSection
                inviteSection
            }
            .navigationTitle("New Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .close) { close() }
                }
            }
            .sheet(isPresented: $showsContacts) {
                ContactPicker { drafts in
                    showsContacts = false
                    finish(model.add(contacts: drafts))
                }
            }
            .sheet(isPresented: $showsScanner) { scannerSheet }
            .alert("Couldn't Add Friend", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .haptic(.success, trigger: addedCount)
        }
        .presentationDetents([.large])
    }

    // MARK: Sections

    private func invitationSection(_ invite: FriendInvite) -> some View {
        Section {
            Button {
                if let result = model.accept(invite) { finish([result]) }
            } label: {
                Label("Add \(invite.name)", systemImage: "person.badge.plus")
            }
        } header: {
            Text("Invitation")
        } footer: {
            Text("\(invite.name) invited you to split costs on Splt.")
        }
    }

    private var nameSection: some View {
        @Bindable var model = model

        return Section {
            HStack {
                TextField("Name", text: $model.name)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit(addByName)
                Button("Add", action: addByName)
                    .disabled(!model.canAddByName)
            }
        } header: {
            Text("Add by Name")
        } footer: {
            Text("They don't need the app yet. Splt keeps their name until they join.")
        }
    }

    private var contactsSection: some View {
        Section {
            Button {
                showsContacts = true
            } label: {
                Label("Choose from Contacts", systemImage: "person.crop.circle.badge.plus")
            }
        } footer: {
            Text("Splt only sees the contacts you pick.")
        }
    }

    private var inviteSection: some View {
        @Bindable var model = model

        return Section {
            TextField("Your name", text: $model.inviteName)
                .textContentType(.givenName)
            if let invite = model.myInvite {
                InviteQRCode(invite: invite)
                    .listRowBackground(Color.clear)
                ShareLink(item: invite.shareMessage) {
                    Label("Share Invite Link", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                scanMessage = nil
                showsScanner = true
            } label: {
                Label("Scan a Friend's Code", systemImage: "qrcode.viewfinder")
            }
        } header: {
            Text("Invite")
        } footer: {
            if model.myInvite == nil {
                Text("Enter your name to make an invite link and a code.")
            } else {
                Text("Show the code to a friend, or send the link. They tap it to add you.")
            }
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            QRScannerView { text in
                if let invite = QRInviteScan.invite(from: text) {
                    showsScanner = false
                    if let result = model.accept(invite) { finish([result]) }
                } else {
                    scanMessage = String(localized: "That isn't a Splt invite.")
                }
            }
            .navigationTitle("Scan Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .close) { showsScanner = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let scanMessage {
                    Text(scanMessage)
                        .padding()
                        .glassEffect(.regular, in: .capsule)
                        .padding()
                }
            }
        }
    }

    // MARK: Actions

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private func addByName() {
        guard let result = model.addByName() else { return }
        finish([result])
    }

    /// Closes the sheet and opens the friend when exactly one was added.
    private func finish(_ results: [AddFriendModel.Result]) {
        guard !results.isEmpty else { return }
        addedCount += 1
        router.pendingInvite = nil
        let single = results.count == 1 ? results.first?.person : nil
        dismiss()
        if let single {
            router.friendsPath = [.friend(single.id.rawValue)]
        }
        router.selectedTab = .friends
    }

    private func close() {
        router.pendingInvite = nil
        dismiss()
    }
}

#if DEBUG
#Preview {
    AddFriendView()
        .environment(Router())
        .environment(\.dataServices, SampleData.previewServices())
}
#endif
