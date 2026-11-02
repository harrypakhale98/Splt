import SpltCore
import SwiftUI

/// Who is in the split, as person chips. Tap to include or remove, long press for who paid.
/// While a receipt item is selected, a tap assigns the item instead.
struct WhoIsInSection: View {
    let model: ExpenseFormModel
    @Environment(\.dynamicTypeSize) private var typeSize
    var onChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(headline)
                    .font(.headline)
                Spacer()
                if model.split.method != .itemized {
                    Button(allIn ? "None" : "Everyone") {
                        if allIn { model.participants = [] } else { model.selectEveryone() }
                        onChange()
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                }
            }
            let ids = model.members.map(\.id)
            if typeSize.isAccessibilitySize {
                FlowLayout(spacing: 8) {
                    ForEach(model.members) { person in chip(for: person, members: ids) }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.members) { person in chip(for: person, members: ids) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .padding(.horizontal, -20)
            }
            if model.split.method != .itemized {
                Text("Touch and hold a person to say who paid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var allIn: Bool { model.participants.count == model.members.count }

    private var headline: LocalizedStringKey {
        if model.split.method == .itemized, let item = model.split.items.first(where: { $0.id == model.selectedItemID }) {
            return "Assign \(model.itemName(item))"
        }
        return "Who's in"
    }

    private func chip(for person: Person, members: [PersonID]) -> some View {
        let selected = isHighlighted(person.id)
        return PersonChip(person: person, members: members, isSelected: selected) {
            model.tapPerson(person.id)
            onChange()
        }
        .overlay(alignment: .topTrailing) {
            if model.isPayer(person.id) {
                Image(systemName: "banknote.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.green, in: .circle)
                    .offset(x: 4, y: -4)
                    .accessibilityHidden(true)
                    .transition(.scale)
            }
        }
        .contextMenu {
            Button("Paid by \(model.displayName(for: person.id))", systemImage: "banknote") {
                model.makeSolePayer(person.id)
                onChange()
            }
            Button(
                model.isPayer(person.id) && model.payer.isMultiple ? "Did not pay" : "Also paid",
                systemImage: "plus.circle"
            ) {
                model.toggleAlsoPaid(person.id)
                onChange()
            }
        }
        .accessibilityValue(model.isPayer(person.id) ? String(localized: "Paid") : "")
        .accessibilityAction(named: Text("Paid by \(model.displayName(for: person.id))")) { model.makeSolePayer(person.id) }
        .accessibilityAction(named: Text("Also paid")) { model.toggleAlsoPaid(person.id) }
    }

    private func isHighlighted(_ id: PersonID) -> Bool {
        if model.split.method == .itemized {
            guard let item = model.split.items.first(where: { $0.id == model.selectedItemID }) else { return false }
            return item.assignees.contains(id)
        }
        return model.participants.contains(id)
    }
}
