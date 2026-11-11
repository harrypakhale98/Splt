import SpltCore
import SwiftUI

/// Reaction emoji offered on every comment, with the name VoiceOver speaks for each.
enum CommentReactions {
    static let choices: [(emoji: String, name: String)] = [
        ("\u{1F44D}", String(localized: "Thumbs up")),
        ("\u{2764}\u{FE0F}", String(localized: "Heart")),
        ("\u{1F602}", String(localized: "Laughing")),
        ("\u{1F62E}", String(localized: "Surprised")),
        ("\u{1F389}", String(localized: "Celebration"))
    ]

    static func name(for emoji: String) -> String {
        choices.first { $0.emoji == emoji }?.name ?? emoji
    }
}

struct CommentsSection: View {
    let model: ExpenseDetailModel
    let translate: (String) -> Void
    @State private var draft = ""

    var body: some View {
        Section {
            RaisedRows {
                ForEach(model.comments) { comment in
                    CommentRow(model: model, comment: comment, translate: translate)
                }
                if model.me != nil {
                    HStack(alignment: .bottom) {
                        TextField("Add a comment", text: $draft, axis: .vertical)
                            .lineLimit(1...5)
                            .submitLabel(.send)
                            .onSubmit(send)
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send comment")
                    }
                }
            }
        } header: {
            SectionHeader("Comments")
        }
    }

    private func send() {
        model.addComment(draft)
        draft = ""
    }
}

private struct CommentRow: View {
    let model: ExpenseDetailModel
    let comment: ExpenseComment
    let translate: (String) -> Void
    @State private var confirmsDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                AvatarView(name: model.people[comment.authorID]?.name ?? "?", id: comment.authorID, members: model.memberIDs, size: 28)
                Text(model.name(for: comment.authorID)).font(.subheadline)
                Spacer(minLength: 8)
                Text(comment.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Ink.secondary)
            }
            Text(comment.text)
            reactions
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .raisedContextMenuShape()
        .contextMenu {
            Button("Translate", systemImage: "translate") { translate(comment.text) }
            if comment.authorID == model.me?.id {
                Button("Delete", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            }
        }
        .confirmationDialog("Delete Comment?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Comment", role: .destructive) { model.deleteComment(comment) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var reactions: some View {
        FlowLayout(spacing: 6) {
            ForEach(grouped, id: \.emoji) { group in
                Button {
                    model.toggleReaction(group.emoji, on: comment)
                } label: {
                    Text("\(group.emoji) \(group.count)")
                        .monospacedDigit()
                        .font(.subheadline)
                        .foregroundStyle(group.mine ? Ink.text : Ink.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay { Capsule().strokeBorder(group.mine ? Ink.text : Ink.hairline) }
                        // The capsule stays small; the tap area around it reaches 44 points.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CommentReactions.name(for: group.emoji))
                .accessibilityValue(group.mine ? "\(group.count), including you" : "\(group.count)")
            }
            Menu {
                ForEach(CommentReactions.choices, id: \.emoji) { choice in
                    Button("\(choice.emoji) \(choice.name)") { model.toggleReaction(choice.emoji, on: comment) }
                }
            } label: {
                Image(systemName: "face.smiling")
                    .foregroundStyle(Ink.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add reaction")
        }
    }

    private var grouped: [(emoji: String, count: Int, mine: Bool)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        var mine: Set<String> = []
        for reaction in comment.reactions {
            if counts[reaction.emoji] == nil { order.append(reaction.emoji) }
            counts[reaction.emoji, default: 0] += 1
            if reaction.person == model.me?.id { mine.insert(reaction.emoji) }
        }
        return order.map { (emoji: $0, count: counts[$0] ?? 0, mine: mine.contains($0)) }
    }
}
