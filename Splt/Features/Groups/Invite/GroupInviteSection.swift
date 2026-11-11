import SpltCore
import SwiftUI

/// The Invite section of group settings. With iCloud sync available it opens the system invite
/// sheet. Without it, only the plain link and QR code are offered. The system sheet belongs to
/// the person who shared the group, so someone who joined is only offered the link.
struct GroupInviteSection: View {
    let groupID: GroupID
    let groupName: String
    var isSharedWithMe = false

    private let runtime = SyncRuntime.shared
    @State private var sharing: GroupSharingModel?
    @State private var didShare = false
    @State private var asksForNotifications = false

    var body: some View {
        Section {
            RaisedRows {
                if runtime.status.isConnected, !isSharedWithMe {
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
                    InviteGroupView(groupID: groupID, groupName: groupName, isSharedWithMe: isSharedWithMe)
                } label: {
                    Label("Link or QR Code", systemImage: "qrcode")
                }
            }
        } header: {
            SectionHeader("Invite")
                .padding(.horizontal, Depth.pageMargin + 4)
        } footer: {
            if !runtime.status.isConnected {
                Text("Turn on iCloud to invite people; a link only opens the group on a device that already has it.")
                    .padding(.horizontal, Depth.pageMargin + 4)
            } else if isSharedWithMe {
                Text("Only the person who shared this group can invite people with iCloud.")
                    .padding(.horizontal, Depth.pageMargin + 4)
            }
        }
        .raisedSection()
        .sheet(item: preparedBinding, onDismiss: {
            // once the invite sheet is gone, the people invited will start adding things
            if didShare, NotificationAsk.shouldAsk() { asksForNotifications = true }
            didShare = false
        }) { prepared in
            CloudSharingView(
                groupShare: prepared.groupShare, onSaved: { didShare = true }, onStopped: { sharing?.prepared = nil }
            )
            .ignoresSafeArea()
        }
        .notificationAsk(isPresented: $asksForNotifications)
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
