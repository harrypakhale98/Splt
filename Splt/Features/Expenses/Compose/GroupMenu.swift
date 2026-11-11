import SpltCore
import SwiftUI

/// Which group a new expense goes to, as a plain line beside who paid. Shown only when there is
/// another group to move to; a direct expense with a friend stays with that friend.
struct GroupMenu: View {
    let model: ExpenseFormModel
    let groups: [SplitGroup]

    var body: some View {
        if let current = model.group {
            Menu {
                Section("Group") {
                    ForEach(groups) { group in
                        Button {
                            model.switchGroup(to: group.id)
                        } label: {
                            if group.id == current.id {
                                Label(group.name, systemImage: "checkmark")
                            } else {
                                Text(group.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(current.name)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .accessibilityLabel("Group")
            .accessibilityValue(current.name)
            .accessibilityHint("Choose the group for this expense")
            .accessibilityIdentifier("expense-group")
        }
    }
}

/// The group line and who paid, side by side, or one above the other when both names are long.
struct GroupAndPayerLine: View {
    let model: ExpenseFormModel
    var onPayerChange: () -> Void = {}

    var body: some View {
        let groups = model.switchableGroups
        if groups.isEmpty {
            PaidByMenu(model: model, onChange: onPayerChange)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    GroupMenu(model: model, groups: groups)
                    Text(verbatim: "·")
                        .font(.subheadline)
                        .foregroundStyle(Ink.secondary)
                        .accessibilityHidden(true)
                    PaidByMenu(model: model, onChange: onPayerChange)
                }
                // the two 44 point tap areas overlap a little so the lines read as a pair
                VStack(spacing: -20) {
                    GroupMenu(model: model, groups: groups)
                    PaidByMenu(model: model, onChange: onPayerChange)
                }
            }
        }
    }
}

extension ExpenseFormModel {
    /// The groups a new expense can move between, or none when the group is fixed.
    var switchableGroups: [SplitGroup] {
        guard group != nil, group?.kind != .friend else { return [] }
        let groups = availableGroups
        return groups.count > 1 ? groups : []
    }
}
