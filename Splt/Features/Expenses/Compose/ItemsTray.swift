import SpltCore
import SwiftUI

/// The items of a scanned or typed bill as outlined rows. Select one, then tap people to assign it.
struct ItemsTray: View {
    @Bindable var model: ExpenseFormModel
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("Items")
                Spacer()
                Button("Edit Items", action: onEdit)
                    .font(.subheadline)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            if let notice = model.scanNotice {
                Label(notice, systemImage: "doc.text.viewfinder")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }
            if model.split.items.isEmpty {
                Button {
                    model.addItem()
                    onEdit()
                } label: {
                    Label("Add Item", systemImage: "plus")
                        .frame(minHeight: 44)
                }
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(model.split.items) { item in
                        pill(for: item)
                    }
                }
                .motion(Motion.snappy, value: model.split.items)
            }
        }
    }

    private func pill(for item: ItemDraft) -> some View {
        let selected = model.selectedItemID == item.id
        let people = model.members.filter { item.assignees.contains($0.id) }
        let money = AmountInput.money(item.amountText, currencyCode: model.currencyCode, locale: model.locale)
        let button = Button {
            model.selectedItemID = selected ? nil : item.id
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.itemName(item)).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let money {
                        Text(MoneyFormatting.magnitudeString(money, locale: model.locale))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Ink.secondary)
                    }
                }
                if people.isEmpty {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(Ink.secondary)
                        .accessibilityHidden(true)
                } else {
                    AvatarStack(people, members: model.members.map(\.id), size: 22, limit: 3, ring: Ink.paper)
                        .motionTransition(.scale)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .overlay {
                RoundedRectangle(cornerRadius: Depth.controlRadius, style: .continuous)
                    .strokeBorder(selected ? Ink.text : Ink.hairline, lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(.rect)
        }
        return button
            .buttonStyle(.plain)
            .motion(Motion.quick, value: selected)
        .contextMenu {
            Button("Everyone", systemImage: "person.3") { model.assignEveryone(to: item.id) }
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.split.items.removeAll { $0.id == item.id }
            }
        }
        .accessibilityLabel(model.itemName(item))
        .accessibilityValue(
            people.isEmpty
                ? String(localized: "Not assigned")
                : String(localized: "Shared by \(people.map(\.name).formatted(.list(type: .and)))")
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Select, then choose who shared it")
    }
}
