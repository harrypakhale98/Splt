import SpltCore
import SwiftUI

/// Invites one person who was added by name, built like Remind: the message, then the ways to send it.
/// The link is made for them, so they see their balance before installing and join as themselves.
struct InvitePersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.groupSharing) private var sharing
    @State private var model: InvitePersonModel
    @State private var copyCount = 0

    init(groupID: GroupID, person: Person, services: DataServices) {
        _model = State(initialValue: InvitePersonModel(groupID: groupID, person: person, services: services))
    }

    var body: some View {
        NavigationStack {
            Form {
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
                            Text("Only people you invited can join this group. An invite link lets anyone who has it join and add expenses.")
                                .foregroundStyle(Ink.secondary)
                            Button("Allow Anyone with the Link", systemImage: "link") {
                                Task { await model.openToAnyone(using: sharing) }
                            }
                        }
                    }
                    .raisedSection()
                case .ready(let link):
                    Section {
                        RaisedRows {
                            Text(model.message)
                                .textSelection(.enabled)
                            ShareLink(
                                item: link,
                                subject: Text("Join \(model.groupName) on Splt"),
                                message: Text(model.message)
                            ) {
                                Label("Send Invite", systemImage: "paperplane")
                            }
                            .accessibilityIdentifier("invite.send")
                            Button("Copy Link", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = model.message + "\n" + link.absoluteString
                                copyCount += 1
                                AccessibilityNotification.Announcement(String(localized: "Link copied")).post()
                            }
                        }
                    } header: {
                        SectionHeader("Message")
                            .padding(.horizontal, Depth.pageMargin + 4)
                    } footer: {
                        Text("The link is made for \(model.firstName), so joining keeps everything already added for \(model.person.name).")
                            .padding(.horizontal, Depth.pageMargin + 4)
                    }
                    .raisedSection()
                case .needsICloud:
                    Section {
                        RaisedRows {
                            Text("Turn on iCloud to invite people.")
                                .foregroundStyle(Ink.secondary)
                        }
                    }
                    .raisedSection()
                case .failed(let message):
                    Section {
                        RaisedRows {
                            Text(message)
                                .foregroundStyle(Ink.secondary)
                        }
                    }
                    .raisedSection()
                }
            }
            .paperBackground()
            .navigationTitle("Invite \(model.firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .close) { dismiss() }
                }
            }
            .haptic(.success, trigger: copyCount)
            .task { await model.load(using: sharing) }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("invite.sheet")
    }
}
