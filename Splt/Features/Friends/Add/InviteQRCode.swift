import SwiftUI

/// Your invite as a QR code that a friend can scan.
struct InviteQRCode: View {
    let invite: FriendInvite

    var body: some View {
        if let image = QRCodeImage.make(from: invite.url.absoluteString) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("QR code that adds \(invite.name) as a friend")
        }
    }
}
