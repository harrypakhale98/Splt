import SpltCore
import SwiftUI

/// One event on the timeline: an unread dot like Mail's, one marker, what happened, where and when.
/// Your own actions show only their symbol, because the sentence already says "You". Other people's show their avatar.
struct ActivityRowView: View {
    let entry: ActivityEntry
    let text: String
    let groupName: String?
    let actor: (id: PersonID, name: String, isMe: Bool)?
    var isFirst = false
    var isLast = false

    @Environment(\.dynamicTypeSize) private var typeSize

    private let dot: CGFloat = 10
    private let rail: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(entry.isRead ? Color.clear : Color.accentColor)
                .frame(width: dot, height: dot)
                .padding(.top, 14)
                .accessibilityHidden(true)
            marker
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let groupName {
                        Text(groupName)
                        Text("\u{00B7}")
                    }
                    Text(entry.createdAt, style: .time)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .background(alignment: .leading) {
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 2)
                .padding(.leading, dot + 8 + rail / 2 - 1)
                .padding(.top, isFirst ? 30 : 0)
                .padding(.bottom, isLast ? 40 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(entry.isRead ? "" : String(localized: "Unread"))
    }

    @ViewBuilder
    private var marker: some View {
        Group {
            if let actor, !actor.isMe {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(name: actor.name, id: actor.id, size: rail - 2)
                    glyph(size: 16)
                        .background(Color(.systemBackground), in: .circle)
                        .overlay { Circle().strokeBorder(Color(.separator), lineWidth: 0.5) }
                        .offset(x: 7, y: 7)
                }
            } else {
                glyph(size: rail - 2)
                    .background(Color.accentColor.opacity(0.16), in: .circle)
            }
        }
        .frame(width: rail, height: rail)
        .padding(.top, 6)
        .accessibilityHidden(true)
    }

    private func glyph(size: CGFloat) -> some View {
        Image(systemName: entry.event.kind.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
    }

    private var accessibilityText: String {
        var parts = [text]
        if let groupName { parts.append(groupName) }
        parts.append(entry.createdAt.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: ", ")
    }
}
