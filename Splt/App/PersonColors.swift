import SwiftUI

extension View {
    /// Keeps the person color book in line with the people in the store.
    func personColors(services: DataServices?) -> some View {
        modifier(PersonColors(services: services))
    }
}

private struct PersonColors: ViewModifier {
    let services: DataServices?
    @State private var observer: ContainerChangeObserver?

    func body(content: Content) -> some View {
        content.task {
            guard let services else { return }
            refresh(services)
            if observer == nil {
                observer = ContainerChangeObserver(container: services.container) { refresh(services) }
            }
        }
    }

    private func refresh(_ services: DataServices) {
        let people = (try? services.people.allPeople()) ?? []
        PersonColorBook.update(people: people, me: (try? services.people.me())?.id)
    }
}
