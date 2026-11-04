import SpltCore
import SwiftUI

/// One group in the list: its mesh glyph, name, who is in it and your balance.
struct GroupRowView: View {
    let summary: GroupSummary
    var members: [Person] = []

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let lines = BalanceLine.lines(for: summary.myBalance)
        let glyph = GroupGlyph(symbol: summary.group.symbol, members: summary.group.memberIDs, size: 52)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    glyph
                    details
                    balance(lines)
                }
            } else {
                HStack(spacing: 14) {
                    glyph
                    details
                    Spacer(minLength: 8)
                    balance(lines)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.group.name)
                .font(.headline)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            if members.isEmpty {
                Text("^[\(summary.memberCount) member](inflect: true)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                AvatarStack(
                    members, members: summary.group.memberIDs, size: 22, limit: 4,
                    ring: Color(.secondarySystemGroupedBackground)
                )
            }
        }
    }

    @ViewBuilder
    private func balance(_ lines: [BalanceLine]) -> some View {
        if lines.isEmpty {
            Label("Settled up", systemImage: "checkmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                ForEach(lines) { line in
                    MoneyLabel(money: line.money, style: .balance)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                    Text(line.direction.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Rows") {
    let services = SampleData.previewServices()
    List(services.groupsStore.summaries) { summary in
        GroupRowView(summary: summary)
    }
}

#Preview("Large text") {
    let services = SampleData.previewServices()
    List(services.groupsStore.summaries.prefix(2)) { summary in
        GroupRowView(summary: summary)
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
