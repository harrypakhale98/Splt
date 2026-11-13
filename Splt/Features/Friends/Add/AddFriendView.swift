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
                EmptyStateView.dataUnavailable
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
            .paperBackground()
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
            .raisedRow()
        } header: {
            SectionHeader("Invitation")
                .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()
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
                // Borderless, so tapping the field's row doesn't press it.
                Button("Add", action: addByName)
                    .buttonStyle(.borderless)
                    .disabled(!model.canAddByName)
            }
            .raisedRow()
        } header: {
            SectionHeader("Add by name")
                .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()
    }

    private var contactsSection: some View {
        Section {
            Button {
                showsContacts = true
            } label: {
                Label("Choose from Contacts", systemImage: "person.crop.circle.badge.plus")
            }
            .raisedRow()
        } footer: {
            Text("The app only sees the contacts you pick.")
                .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()
    }

    private var inviteSection: some View {
        @Bindable var model = model

        return Section {
            TextField("Your Name", text: $model.inviteName)
                .textContentType(.givenName)
                .raisedRow()
            // The code is a card of its own, so it sits on paper between the two cards.
            if let invite = model.myInvite {
                InviteQRCode(invite: invite)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            RaisedRows {
                if let invite = model.myInvite {
                    ShareLink(item: invite.shareMessage, subject: Text("Add me on Splt")) {
                        Label("Share Invite Link", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    scanMessage = nil
                    showsScanner = true
                } label: {
                    Label("Scan a Friend's Code", systemImage: "qrcode.viewfinder")
                }
            }
        } header: {
            SectionHeader("Invite")
                .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()
    }

    private var scannerSheet: some View {
        NavigationStack {
            QRScannerView { text in
                guard let invite = QRInviteScan.invite(from: text) else {
                    scanMessage = String(localized: "That code isn't an invite.")
                    return false
                }
                showsScanner = false
                if let result = model.accept(invite) { finish([result]) }
                return true
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
                        .cardSurface()
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
