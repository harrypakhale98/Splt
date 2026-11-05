import SpltCore
import SwiftUI

/// One event on the feed: what happened in a sentence, a quiet group and time line, and a small mark.
/// An unread event has a dot in the margin, like Mail.
struct ActivityRowView: View {
    let entry: ActivityEntry
    let text: String
    let groupName: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(entry.isRead ? Color.clear : Ink.text)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.leading)
                caption
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: entry.event.kind.symbol)
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(entry.isRead ? "" : String(localized: "Unread"))
    }

    /// Group and time on one line, wrapping at large sizes instead of clipping.
    @ViewBuilder
    private var caption: some View {
        if let groupName {
            Text("\(groupName) \u{00B7} \(entry.createdAt, style: .time)")
        } else {
            Text(entry.createdAt, style: .time)
        }
    }

    private var accessibilityText: String {
        var parts = [text]
        if let groupName { parts.append(groupName) }
        parts.append(entry.createdAt.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: ", ")
    }
}
