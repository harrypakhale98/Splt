import SpltCore
import SwiftUI

/// Invites people added by name, built like Remind: the message, then the ways to send it. The link is
/// made for one person, or for the whole group chat where each person picks themselves, so they see their
/// balance before installing and join as themselves.
struct InvitePersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.groupSharing) private var sharing
    @State private var model: InvitePersonModel
    @State private var copyCount = 0
    @State private var composing = false

    init(groupID: GroupID, invitee: Invitee, services: DataServices) {
        _model = State(initialValue: InvitePersonModel(groupID: groupID, invitee: invitee, services: services))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.state {
                case .loading:
                    note {
                        HStack {
                            ProgressView()
                            Text("Preparing invite")
                                .foregroundStyle(Ink.secondary)
                        }
                    }
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
                case .ready(let links):
                    message(links)
                    if model.person == nil, !model.waiting.isEmpty {
                        waitingSection
                    }
                case .needsICloud:
                    note { Text("Turn on iCloud to invite people.").foregroundStyle(Ink.secondary) }
                case .failed(let message):
                    note { Text(message).foregroundStyle(Ink.secondary) }
                }
            }
            .paperBackground()
            .navigationTitle(model.title)
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

    private func note(@ViewBuilder _ content: () -> some View) -> some View {
        Section {
            RaisedRows { content() }
        }
        .raisedSection()
    }

    // MARK: Ready

    private func message(_ links: InvitePersonModel.Links) -> some View {
        let direct = model.recipient.flatMap { InviteComposer.canSend(to: $0) ? $0 : nil }
        return Section {
            RaisedRows {
                Text(model.message)
                    .textSelection(.enabled)
                if let direct {
                    Button("Send Invite", systemImage: "paperplane") { composing = true }
                        .accessibilityIdentifier("invite.send")
                        .sheet(isPresented: $composing) {
                            InviteComposer(
                                recipient: direct, subject: subject, body: model.text(with: links.send)
                            ) { composing = false }
                            .ignoresSafeArea()
                        }
                    shareLink(links.send) {
                        Label("Other Ways to Send", systemImage: "square.and.arrow.up")
                    }
                } else {
                    shareLink(links.send) {
                        Label("Send Invite", systemImage: "paperplane")
                    }
                    .accessibilityIdentifier("invite.send")
                }
                Button("Copy Link", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = model.text(with: links.send)
                    copyCount += 1
                    AccessibilityNotification.Announcement(String(localized: "Link copied")).post()
                }
                NavigationLink {
                    InviteQRView(link: links.scan, caption: qrCaption)
                } label: {
                    Label("Show QR Code", systemImage: "qrcode")
                }
                .accessibilityIdentifier("invite.qr")
            }
        } header: {
            SectionHeader("Message")
                .padding(.horizontal, Depth.pageMargin + 4)
        } footer: {
            Text(footer(direct: direct))
                .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()
    }

    private func shareLink(_ link: URL, @ViewBuilder label: () -> some View) -> some View {
        ShareLink(item: link, subject: Text(subject), message: Text(model.message), label: label)
    }

    private var waitingSection: some View {
        Section {
            RaisedRows {
                ForEach(model.waiting) { person in
                    HStack(spacing: 12) {
                        AvatarView(person: person, size: 28)
                        Text(person.name)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            SectionHeader("Not on Splt yet")
                .padding(.horizontal, Depth.pageMargin + 4)
        }
        .raisedSection()
    }

    private var subject: String {
        String(localized: "Join \(model.groupName) on Splt")
    }

    private func footer(direct: InvitePersonModel.Recipient?) -> String {
        guard let person = model.person else {
            return String(localized: "Send it to the group chat. Each person picks their own name, so they keep everything already added for them.")
        }
        let base = String(localized: "The link is made for \(model.firstName), so joining keeps everything already added for \(person.name).")
        guard let direct else { return base }
        return base + " " + String(localized: "Send Invite writes to \(direct.address).")
    }

    private var qrCaption: String {
        if model.person == nil {
            return String(localized: "Anyone not on Splt yet can scan this with the iPhone camera, then pick their name.")
        }
        return String(localized: "\(model.firstName) can scan this with the iPhone camera to open the invite.")
    }
}

/// The invite as a QR code, for inviting someone in person.
private struct InviteQRView: View {
    let link: URL
    let caption: String

    var body: some View {
        List {
            Section {
                RaisedRows {
                    QRCard(text: link.absoluteString)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("QR code for the invite")
                        .accessibilityAddTraits(.isImage)
                }
            } footer: {
                Text(caption)
                    .padding(.horizontal, Depth.pageMargin + 4)
            }
            .raisedSection()
        }
        .paperBackground()
        .navigationTitle("QR Code")
        .navigationBarTitleDisplayMode(.inline)
    }
}
