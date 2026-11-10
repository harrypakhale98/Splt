import SpltCore
import SwiftUI

/// People as toggle buttons that wrap across lines, in the same style as "Who's in".
struct PeopleChips: View {
    let people: [Person]
    let selected: Set<PersonID>
    let currentPerson: PersonID?
    let toggle: (PersonID) -> Void

    var body: some View {
        let ids = people.map(\.id)
        FlowLayout(spacing: 8) {
            ForEach(people) { person in
                PersonToggle(person: person, name: person.name, members: ids, isSelected: selected.contains(person.id)) {
                    toggle(person.id)
                }
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
