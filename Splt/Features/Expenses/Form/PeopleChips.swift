import SpltCore
import SwiftUI

/// People as toggle buttons that wrap across lines. Selected people are filled.
struct PeopleChips: View {
    let people: [Person]
    let selected: Set<PersonID>
    let currentPerson: PersonID?
    let toggle: (PersonID) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(people) { person in
                let name = person.id == currentPerson ? String(localized: "You") : person.name
                Toggle(isOn: Binding(get: { selected.contains(person.id) }, set: { _ in toggle(person.id) })) {
                    Label {
                        Text(name)
                    } icon: {
                        AvatarView(name: person.name, size: 22)
                    }
                }
                .toggleStyle(.button)
                .buttonBorderShape(.capsule)
                .accessibilityLabel(name)
            }
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview("Chips") {
    let people = ["Jamie Rivera", "Maya Chen", "Jonas Weber", "Priya Nair", "Diego Alvarez", "Hana Sato"]
        .map { Person(name: $0) }
    return List {
        PeopleChips(people: people, selected: Set(people.prefix(3).map(\.id)), currentPerson: people[0].id) { _ in }
    }
}
#endif
