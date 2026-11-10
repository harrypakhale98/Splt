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
