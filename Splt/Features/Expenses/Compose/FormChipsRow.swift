import SpltCore
import SwiftUI

enum FormSheet: String, Identifiable {
    case category, date, note, receipt, repeating, currency, more
    /// The receipt items alone, opened from the items tray.
    case items

    var id: String { rawValue }
}

/// The row of plain options under the split: each opens a small sheet.
struct FormChipsRow: View {
    let model: ExpenseFormModel
    var open: (FormSheet) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                groupChip
                chip(.category, model.category.title, model.category.symbolName)
                if !model.isEditingRecurring {
                    chip(.date, dateText, "calendar")
                }
                chip(.currency, model.currencyCode, "coloncurrencysign.circle")
                chip(.note, model.note.isEmpty ? String(localized: "Note") : String(localized: "Note added"), "note.text")
                if model.canAttachReceipt {
                    chip(
                        .receipt, model.receipt.isEmpty ? String(localized: "Receipt") : String(localized: "Receipt added"),
                        model.receipt.isEmpty ? "doc.text.viewfinder" : "doc.text.image.fill"
                    )
                }
                if showsRepeat {
                    chip(.repeating, model.repeatChoice.frequency?.shortTitle ?? String(localized: "Repeat"), "repeat")
                }
                chip(.more, String(localized: "More"), "ellipsis")
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// Where a new expense goes. A direct expense with a friend stays with that friend.
    @ViewBuilder
    private var groupChip: some View {
        let groups = model.availableGroups
        if model.group?.kind != .friend, groups.count > 1, let current = model.group {
            Menu {
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
            } label: {
                Label(current.name, systemImage: "person.3")
                    .font(.subheadline)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Group")
            .accessibilityValue(current.name)
            .accessibilityIdentifier("chip-group")
        }
    }

    private var showsRepeat: Bool {
        if case .add = model.mode { return true }
        return model.isEditingRecurring
    }

    private var dateText: String {
        if Calendar.current.isDateInToday(model.date) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(model.date) { return String(localized: "Yesterday") }
        return model.date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func chip(_ sheet: FormSheet, _ title: String, _ symbol: String) -> some View {
        Button { open(sheet) } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chip-\(sheet.rawValue)")
    }
}

extension RecurrenceFrequency {
    var shortTitle: String {
        switch self {
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .biweekly: String(localized: "Every 2 weeks")
        case .semiMonthly: String(localized: "Twice a month")
        case .monthly: String(localized: "Monthly")
        case .quarterly: String(localized: "Quarterly")
        case .yearly: String(localized: "Yearly")
        }
    }
}
