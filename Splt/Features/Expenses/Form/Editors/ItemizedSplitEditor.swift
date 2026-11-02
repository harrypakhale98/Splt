import SpltCore
import SwiftUI

struct ItemizedSplitEditor: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            if let notice = model.scanNotice {
                Label(notice, systemImage: "doc.text.viewfinder")
                    .font(.footnote)
                    .foregroundStyle(.legible)
            }
            ForEach($model.split.items) { $item in
                ItemRow(model: model, item: $item)
            }
            .onDelete(perform: model.removeItems)
            Button {
                model.addItem()
            } label: {
                Label("Add Item", systemImage: "plus.circle")
            }
        } header: {
            Text("Items").foregroundStyle(.legible)
        }

        Section {
            chargeField("Tax", text: $model.split.taxText)
            chargeField("Tip", text: $model.split.tipText)
            chargeField("Discount", text: $model.split.discountText)
            if let remaining = model.splitRemaining {
                RemainingRow(remaining: remaining, title: "Difference from total")
                if !remaining.isZero {
                    Button("Use Items Total as Amount", action: model.useItemsAsTotal)
                }
            }
        } header: {
            Text("Tax, Tip and Discount").foregroundStyle(.legible)
        } footer: {
            Text("These are shared in proportion to what each person ordered.").foregroundStyle(.legible)
        }
    }

    private func chargeField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text("0"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}

private struct ItemRow: View {
    let model: ExpenseFormModel
    @Binding var item: ItemDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    nameField
                    priceField.frame(maxWidth: 110)
                }
                VStack(alignment: .leading) {
                    nameField
                    priceField
                }
            }
            PeopleChips(
                people: model.members, selected: item.assignees,
                currentPerson: model.me?.id
            ) { person in
                model.assign(person, to: item.id)
            }
            Button(item.assignees.count == model.members.count ? "Clear" : "Everyone") {
                model.assignEveryone(to: item.id)
            }
            .buttonStyle(.borderless)
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }

    private var nameField: some View {
        TextField("Item", text: $item.name, prompt: Text("Item name"))
    }

    private var priceField: some View {
        TextField("Price", text: $item.amountText, prompt: Text("0"))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .accessibilityLabel("Price of \(model.itemName(item))")
    }
}
