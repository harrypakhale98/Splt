import SpltCore
import SwiftUI

/// An avatar and a name on a glass capsule that can be selected, for choosing who is in.
/// Selection shows as a person-colored tint and a check mark, so color is never the only cue.
struct PersonChip: View {
    let name: String
    let id: PersonID
    var members: [PersonID] = []
    var isSelected: Bool
    var action: () -> Void

    init(person: Person, members: [PersonID] = [], isSelected: Bool, action: @escaping () -> Void) {
        name = person.name
        id = person.id
        self.members = members
        self.isSelected = isSelected
        self.action = action
    }

    init(name: String, id: PersonID, members: [PersonID] = [], isSelected: Bool, action: @escaping () -> Void) {
        self.name = name
        self.id = id
        self.members = members
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            GlassPill(
                tint: isSelected ? PersonPalette.color(for: id, in: members.isEmpty ? [id] : members) : nil,
                isInteractive: true
            ) {
                HStack(spacing: 8) {
                    AvatarView(name: name, id: id, members: members, size: 28)
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .haptics(.tick, trigger: isSelected)
    }
}

#Preview {
    let people = ["Sam Rivera", "Priya Nair", "Alex Chen"].map { Person(name: $0) }
    let ids = people.map(\.id)
    ScrollView(.horizontal) {
        HStack {
            PersonChip(person: people[0], members: ids, isSelected: true) {}
            PersonChip(person: people[1], members: ids, isSelected: false) {}
            PersonChip(person: people[2], members: ids, isSelected: true) {}
        }
        .padding()
    }
}
