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
