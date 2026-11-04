import SpltCore
import SwiftUI

/// The Invite section of group settings. People are invited through iCloud with the system invite
/// sheet, the only way that lets them in. While that is not possible, it says why.
struct GroupInviteSection: View {
    let groupID: GroupID
    let groupName: String

    private let runtime = SyncRuntime.shared
    @State private var sharing: GroupSharingModel?

    var body: some View {
        Section {
            Button(action: prepare) {
                HStack {
                    Label("Invite with iCloud", systemImage: "person.badge.plus")
                    if sharing?.phase == .preparing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            // the row otherwise keeps full-strength text and reads as tappable while it is off
            .foregroundStyle(runtime.status.isConnected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .disabled(!runtime.status.isConnected || sharing?.phase == .preparing)
        } header: {
            Text("Invite")
        } footer: {
            if let note = Self.note(for: runtime.status) {
                Text(note)
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

    /// Why inviting is not possible right now, or nil when it is.
    static func note(for status: SyncStatus) -> String? {
        switch status {
        case .idle, .syncing: nil
        case .offline: String(localized: "You're offline. Connect to the internet to invite people.")
        case .noAccount: String(localized: "Sign in to iCloud in the Settings app to invite people.")
        case .restricted: String(localized: "iCloud is restricted on this device, so you can't invite people.")
        case .error: String(localized: "iCloud sync needs attention before you can invite people. Open Account to see why.")
        case .unavailable: String(localized: "Inviting people needs iCloud, which this build of Splt can't use.")
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
