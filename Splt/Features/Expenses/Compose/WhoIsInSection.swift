import SpltCore
import SwiftUI

/// Who is in the split, as plain names. Tap to include or remove, long press for who paid.
/// While a receipt item is selected, a tap assigns the item instead.
struct WhoIsInSection: View {
    let model: ExpenseFormModel
    @Environment(\.dynamicTypeSize) private var typeSize
    var onChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline)
                    .font(.headline)
                Spacer()
                if model.split.method != .itemized {
                    Button(allIn ? "None" : "Everyone") {
                        if allIn { model.participants = [] } else { model.selectEveryone() }
                        onChange()
                    }
                    .font(.subheadline)
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
                    HStack(spacing: 20) {
                        ForEach(model.members) { person in chip(for: person, members: ids) }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .padding(.horizontal, -20)
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
        var shown = person
        if typeSize.isAccessibilitySize, let first = person.name.split(separator: " ").first {
            shown.name = String(first)
        }
        return PersonToggle(person: shown, members: members, isSelected: isHighlighted(person.id)) {
            model.tapPerson(person.id)
            onChange()
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
        .accessibilityLabel(person.name)
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

/// A small avatar and a name. Selected people are in ink with a check and an underline,
/// and the others are dimmed, so the state never rests on color alone.
private struct PersonToggle: View {
    let person: Person
    let members: [PersonID]
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    AvatarView(person: person, members: members, size: 24)
                        .opacity(isSelected ? 1 : 0.4)
                    Text(person.name)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Ink.text : Ink.secondary)
                        .lineLimit(1)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Ink.text)
                            .accessibilityHidden(true)
                    }
                }
                Rectangle()
                    .fill(isSelected ? Ink.text : Color.clear)
                    .frame(height: 1)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .motion(Motion.quick, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .haptics(.tick, trigger: isSelected)
    }
}
