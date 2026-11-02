import SpltCore
import SwiftUI

/// One event on the timeline: an unread dot like Mail's, the actor's avatar on a rail, what happened, where and when.
struct ActivityRowView: View {
    let entry: ActivityEntry
    let text: String
    let groupName: String?
    let actor: (id: PersonID, name: String)?
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
                    .fontWeight(entry.isRead ? .regular : .medium)
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

    private var marker: some View {
        ZStack(alignment: .bottomTrailing) {
            if let actor {
                AvatarView(name: actor.name, id: actor.id, size: rail - 2, showsInitials: true)
            } else {
                Circle().fill(Color(.tertiarySystemFill))
                    .frame(width: rail - 2, height: rail - 2)
            }
            Image(systemName: entry.event.kind.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 16, height: 16)
                .background(Color(.systemBackground), in: .circle)
                .overlay { Circle().strokeBorder(Color(.separator), lineWidth: 0.5) }
                .offset(x: 7, y: 7)
        }
        .frame(width: rail, height: rail)
        .padding(.top, 6)
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        var parts = [text]
        if let groupName { parts.append(groupName) }
        parts.append(entry.createdAt.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: ", ")
    }
}
