import Foundation
import Observation
import SpltCore

/// The state behind the Link or QR Code screen. Asking for the link opens a share to anyone who has
/// it, so a share its owner limited to invited people is left alone until they ask.
@MainActor
@Observable
final class InviteLinkModel {
    enum State: Equatable {
        case loading
        /// The share exists and only invited people can join. Nothing was changed.
        case inviteOnly
        case ready(URL)
        case failed(String)
    }

    let groupID: GroupID
    let groupName: String
    private(set) var state: State = .loading

    init(groupID: GroupID, groupName: String) {
        self.groupID = groupID
        self.groupName = groupName
    }

    func load(using sharing: any GroupSharing) async {
        do {
            if try await sharing.isInviteOnly(groupID: groupID) {
                state = .inviteOnly
            } else {
                state = .ready(try await sharing.inviteURL(for: groupID, groupName: groupName))
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The owner asked for a link anyone can use, so the share is opened and the link shown.
    func openToAnyone(using sharing: any GroupSharing) async {
        state = .loading
        do {
            state = .ready(try await sharing.inviteURL(for: groupID, groupName: groupName))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
