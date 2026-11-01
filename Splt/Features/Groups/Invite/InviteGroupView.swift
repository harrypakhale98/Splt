import SpltCore
import SwiftUI

/// A link and QR code for inviting people to a group.
struct InviteGroupView: View {
    let groupID: GroupID
    let groupName: String

    @Environment(\.groupSharing) private var sharing
    @State private var state: LoadState = .loading
    @State private var copyCount = 0

    private enum LoadState {
        case loading
        case ready(URL, UIImage?)
        case failed(String)
    }

    var body: some View {
        List {
            switch state {
            case .loading:
                HStack {
                    ProgressView()
                    Text("Preparing invite")
                        .foregroundStyle(.secondary)
                }
            case .ready(let url, let image):
                Section {
                    if let image {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("QR code to join \(groupName)")
                    }
                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Section {
                    ShareLink(
                        item: url,
                        subject: Text("Join \(groupName) on Splt"),
                        message: Text("Join \(groupName) on Splt.")
                    ) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                    }
                    Button("Copy Link", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = url.absoluteString
                        copyCount += 1
                    }
                }
            case .failed(let message):
                ContentUnavailableView(
                    "Can't Invite Yet",
                    systemImage: "person.badge.plus",
                    description: Text(message)
                )
            }
        }
        .navigationTitle("Invite")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.success, trigger: copyCount)
        .task { await load() }
    }

    private func load() async {
        do {
            let url = try await sharing.inviteURL(for: groupID, groupName: groupName)
            state = .ready(url, QRCodeImage.make(from: url.absoluteString))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        InviteGroupView(groupID: GroupID(), groupName: "Lisbon Trip")
    }
}
