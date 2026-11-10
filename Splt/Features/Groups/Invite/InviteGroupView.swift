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
        case ready(URL)
        case failed(String)
    }

    var body: some View {
        List {
            switch state {
            case .loading:
                Section {
                    RaisedRows {
                        HStack {
                            ProgressView()
                            Text("Preparing invite")
                                .foregroundStyle(Ink.secondary)
                        }
                    }
                }
                .raisedSection()
            case .ready(let url):
                Section {
                    RaisedRows {
                        QRCard(text: url.absoluteString)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("QR code to join \(groupName)")
                            .accessibilityAddTraits(.isImage)
                        Text(url.absoluteString)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Ink.secondary)
                            .textSelection(.enabled)
                    }
                }
                .raisedSection()
                Section {
                    RaisedRows {
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
                } footer: {
                    Text(footer(for: url))
                        .padding(.horizontal, Depth.pageMargin + 4)
                }
                .raisedSection()
            case .failed(let message):
                EmptyStateView(
                    title: "Can't Invite Yet",
                    systemImage: "person.badge.plus",
                    description: "\(message)"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .paperBackground()
        .navigationTitle("Invite")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.success, trigger: copyCount)
        .task { await load() }
    }

    /// The iCloud link lets anyone join; the plain app link only opens the group where it already is.
    private func footer(for url: URL) -> LocalizedStringKey {
        if url.scheme == DeepLink.scheme {
            "Turn on iCloud to invite people. This link only opens the group on a device that already has it."
        } else {
            "Anyone with this link can join and add expenses. To stop that, open Invite with iCloud and change who can join."
        }
    }

    private func load() async {
        do {
            let url = try await sharing.inviteURL(for: groupID, groupName: groupName)
            state = .ready(url)
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
