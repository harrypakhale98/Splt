import SwiftUI

/// Your invite as a QR code that a friend can scan.
struct InviteQRCode: View {
    let invite: FriendInvite

    var body: some View {
        QRCard(text: invite.url.absoluteString, maxWidth: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("QR code that adds \(invite.name) as a friend")
            .accessibilityAddTraits(.isImage)
    }
}
