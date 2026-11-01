import SpltCore
import SwiftUI

struct ItemizedSplitEditor: View {
    @Bindable var model: ExpenseFormModel

    var body: some View {
        Section {
            if let notice = model.scanNotice {
                Label(notice, systemImage: "doc.text.viewfinder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            Text("Items")
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
            Text("Tax, Tip and Discount")
        } footer: {
            Text("These are shared in proportion to what each person ordered.")
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
            HStack {
                TextField("Item", text: $item.name, prompt: Text("Item name"))
                TextField("Price", text: $item.amountText, prompt: Text("0"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 110)
                    .accessibilityLabel("Price of \(model.itemName(item))")
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
}
