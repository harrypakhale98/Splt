import SpltCore
import SwiftUI

/// The items of a scanned or typed bill as glass pills. Select one, then tap people to assign it.
struct ItemsTray: View {
    @Bindable var model: ExpenseFormModel
    var onEdit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Items").font(.headline)
                Spacer()
                Button("Edit Items", action: onEdit)
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            if let notice = model.scanNotice {
                Label(notice, systemImage: "doc.text.viewfinder")
                    .font(.footnote)
                    .foregroundStyle(.legible)
            }
            if model.split.items.isEmpty {
                Button {
                    model.addItem()
                    onEdit()
                } label: {
                    Label("Add Items", systemImage: "plus")
                }
                .buttonStyle(.glass)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(model.split.items) { item in
                        pill(for: item)
                    }
                }
                .animation(reduceMotion ? nil : Motion.snappy, value: model.split.items)
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
                            .foregroundStyle(.legible)
                    }
                }
                if people.isEmpty {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                } else {
                    AvatarStack(people, members: model.members.map(\.id), size: 22, limit: 3)
                        .transition(.scale)
                }
            }
            .padding(.horizontal, 4)
        }
        return Group {
            if selected {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.glass)
            }
        }
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
