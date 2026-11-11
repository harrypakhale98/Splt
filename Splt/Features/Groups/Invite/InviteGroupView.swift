import SpltCore
import SwiftUI

/// A link and QR code for inviting people to a group.
struct InviteGroupView: View {
    @Environment(\.groupSharing) private var sharing
    @State private var asksForNotifications = false
    @State private var model: InviteLinkModel
    @State private var copyCount = 0

    /// True in a group someone else shared, where only they can change who may join.
    private let isSharedWithMe: Bool

    init(groupID: GroupID, groupName: String, isSharedWithMe: Bool = false) {
        _model = State(initialValue: InviteLinkModel(groupID: groupID, groupName: groupName))
        self.isSharedWithMe = isSharedWithMe
    }

    private var groupName: String { model.groupName }

    var body: some View {
        List {
            switch model.state {
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
            case .inviteOnly:
                Section {
                    RaisedRows {
                        Text("Only people you invited can join this group. A link or QR code lets anyone who has it join and add expenses.")
                            .foregroundStyle(Ink.secondary)
                        Button("Allow Anyone with the Link", systemImage: "link") {
                            Task { await model.openToAnyone(using: sharing) }
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
                            AccessibilityNotification.Announcement(String(localized: "Link copied")).post()
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
        .task { await model.load(using: sharing) }
        .onChange(of: model.state) { _, state in
            // a link anyone can join is ready to send, so changes from new people are on their way
            if case .ready(let url) = state, url.scheme != DeepLink.scheme, NotificationAsk.shouldAsk() {
                asksForNotifications = true
            }
        }
        .notificationAsk(isPresented: $asksForNotifications)
    }

    /// The iCloud link lets anyone join; the plain app link only opens the group where it already is.
    private func footer(for url: URL) -> LocalizedStringKey {
        if url.scheme == DeepLink.scheme {
            "Turn on iCloud to invite people. This link only opens the group on a device that already has it."
        } else if isSharedWithMe {
            "Anyone with this link can join and add expenses. Only the person who shared this group can stop that."
        } else {
            "Anyone with this link can join and add expenses. To stop that, open Invite with iCloud and change who can join. That also removes everyone who joined with the link."
        }
    }
}

#Preview {
    NavigationStack {
        InviteGroupView(groupID: GroupID(), groupName: "Lisbon Trip")
    }
}
