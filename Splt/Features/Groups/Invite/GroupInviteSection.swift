import SpltCore
import SwiftUI

/// The Invite section of group settings. With iCloud sync available it opens the system invite
/// sheet. Without it, only the plain link and QR code are offered.
struct GroupInviteSection: View {
    let groupID: GroupID
    let groupName: String

    private let runtime = SyncRuntime.shared
    @State private var sharing: GroupSharingModel?

    var body: some View {
        Section {
            if runtime.status.isConnected {
                Button(action: prepare) {
                    HStack {
                        Label("Invite with iCloud", systemImage: "person.badge.plus")
                        if sharing?.phase == .preparing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(sharing?.phase == .preparing)
            }
            NavigationLink {
                InviteGroupView(groupID: groupID, groupName: groupName)
            } label: {
                Label("Invite with Link or QR Code", systemImage: "qrcode")
            }
        } header: {
            Text("Invite")
        } footer: {
            if !runtime.status.isConnected {
                Text("Turn on iCloud to invite people straight from Splt. The link only opens this group on a device that already has it.")
            }
        }
        .sheet(item: preparedBinding) { prepared in
            CloudSharingView(groupShare: prepared.groupShare, onStopped: { sharing?.prepared = nil })
                .ignoresSafeArea()
        }
        .alert("Couldn't Invite", isPresented: failureBinding) {
            Button("OK", role: .cancel) { sharing?.dismissError() }
        } message: {
            Text(failureMessage)
        }
    }

    private func prepare() {
        let model = GroupSharingModel(engine: runtime.engine)
        sharing = model
        Task { await model.prepare(group: groupID) }
    }

    private var preparedBinding: Binding<GroupSharingModel.Prepared?> {
        Binding(get: { sharing?.prepared }, set: { sharing?.prepared = $0 })
    }

    private var failureMessage: String {
        if case .failed(let message) = sharing?.phase { message } else { "" }
    }

    private var failureBinding: Binding<Bool> {
        Binding(
            get: { if case .failed = sharing?.phase { true } else { false } },
            set: { if !$0 { sharing?.dismissError() } }
        )
    }
}

#Preview {
    Form {
        GroupInviteSection(groupID: GroupID(), groupName: "Lisbon Trip")
    }
}
