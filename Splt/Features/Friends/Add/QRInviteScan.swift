import Foundation

enum QRInviteScan {
    /// The invite inside scanned text, or nil when the code is something else.
    static func invite(from text: String) -> FriendInvite? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              case .invite(let invite)? = DeepLink(url: url) else { return nil }
        return invite
    }
}
