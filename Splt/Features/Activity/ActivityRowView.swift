import SwiftUI

/// One event: an unread dot, what happened, where and when.
struct ActivityRowView: View {
    let entry: ActivityEntry
    let text: String
    let groupName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(entry.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 8)
                .accessibilityHidden(true)
            Image(systemName: entry.event.kind.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let groupName {
                        Text(groupName)
                    }
                    Text(entry.createdAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(entry.isRead ? "" : String(localized: "Unread"))
    }

    private var accessibilityText: String {
        var parts = [text]
        if let groupName { parts.append(groupName) }
        parts.append(entry.createdAt.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: ", ")
    }
}
