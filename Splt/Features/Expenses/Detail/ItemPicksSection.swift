import SpltCore
import SwiftUI

/// The items of a bill split by item, with who picked each, and the way to pick your own.
struct ItemPicksSection: View {
    let model: ExpenseDetailModel
    let split: ItemizedSplit
    @State private var isPicking = false

    var body: some View {
        Section {
            RaisedRows {
                ForEach(split.items) { item in
                    ItemPickRow(model: model, item: item)
                }
                if model.canPickItems {
                    Button {
                        isPicking = true
                    } label: {
                        Label("Pick Your Items", systemImage: "checklist")
                    }
                }
            }
        } header: {
            SectionHeader("Items")
        } footer: {
            if let name = model.waitingForName {
                Text("Waiting for \(name) to update the split.")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }
        }
        // a plain list draws a section footer on white, not on the paper behind it
        .listRowBackground(Ink.paper)
        .sheet(isPresented: $isPicking) {
            PickItemsSheet(items: split.items, initial: model.myPicks, creator: model.creatorName) {
                model.savePicks($0)
            }
        }
    }
}

private struct ItemPickRow: View {
    let model: ExpenseDetailModel
    let item: SplitItem
    @Environment(\.locale) private var locale

    var body: some View {
        let pickers = model.pickers(of: item.id).map(model.name(for:))
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? String(localized: "Item") : item.name)
                if !pickers.isEmpty {
                    Text("Picked by \(pickers.formatted(.list(type: .and).locale(locale)))")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                }
            }
            Spacer(minLength: 8)
            SignedAmount(money: item.amount).font(Typeface.figure)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tick the items you had. Saving stores only your picks; the person who added the expense
/// updates the split from them.
struct PickItemsSheet: View {
    let items: [SplitItem]
    let creator: String?
    let save: (Set<UUID>) -> Void
    private let initial: Set<UUID>
    @State private var selected: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    init(items: [SplitItem], initial: Set<UUID>, creator: String?, save: @escaping (Set<UUID>) -> Void) {
        self.items = items
        self.creator = creator
        self.save = save
        self.initial = initial
        _selected = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RaisedRows {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                } header: {
                    SectionHeader("What did you have?")
                } footer: {
                    Group {
                        if let creator {
                            Text("Tax, tip and discount follow your items. \(creator) updates the split from everyone's picks.")
                        } else {
                            Text("Tax, tip and discount follow your items.")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                }
                .listRowBackground(Ink.paper)
            }
            .listStyle(.plain)
            .paperBackground()
            .navigationTitle("Pick Your Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(selected)
                        dismiss()
                    }
                    .disabled(selected.isEmpty || selected == initial)
                }
            }
        }
    }

    private func row(_ item: SplitItem) -> some View {
        let isSelected = selected.contains(item.id)
        return Button {
            Haptics.play(.tick)
            if isSelected { selected.remove(item.id) } else { selected.insert(item.id) }
        } label: {
            HStack {
                Text(item.name.isEmpty ? String(localized: "Item") : item.name)
                Spacer(minLength: 8)
                SignedAmount(money: item.amount).font(Typeface.figure)
                // always laid out, so the price does not move when the check comes and goes
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Ink.text)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
