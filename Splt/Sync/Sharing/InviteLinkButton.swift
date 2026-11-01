import SwiftUI

/// Sends the invitation link through the system share sheet, for friends who are not in your contacts.
/// The link only works for people you added in the invite sheet.
struct InviteLinkButton: View {
    let url: URL
    let groupName: String

    var body: some View {
        ShareLink(
            item: url,
            subject: Text("Join \(groupName) on Splt"),
            message: Text("Join \(groupName) on Splt to split costs together.")
        ) {
            Label("Invite with Link", systemImage: "link")
        }
    }
}
