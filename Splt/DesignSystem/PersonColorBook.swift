import Observation
import SpltCore
import Synchronization

/// The one list of who has which hue. It is filled from the people in the store, you first on the
/// brand teal, then everyone else by when they were added, so every screen and every device
/// agrees. Adding a person never changes the hue of someone who is already there.
enum PersonColorBook {
    private static let hues = Mutex<[PersonID: Int]>([:])

    static func index(for person: PersonID) -> Int? {
        hues.withLock { $0[person] }
    }

    /// The hues for these people, without storing them.
    static func assign(_ people: [Person], me: PersonID?) -> [PersonID: Int] {
        var result: [PersonID: Int] = [:]
        var reserved = Set<Int>()
        if let me {
            result[me] = PersonPalette.meIndex
            reserved.insert(PersonPalette.meIndex)
        }
        let ordered = people
            .filter { $0.id != me }
            .sorted { lhs, rhs in
                lhs.createdAt == rhs.createdAt ? lhs.id.description < rhs.id.description : lhs.createdAt < rhs.createdAt
            }
        for (id, hue) in PersonPalette.resolve(ordered.map(\.id), reserved: reserved) { result[id] = hue }
        return result
    }

    /// Stores the hues and tells views to redraw when anything changed.
    @MainActor
    static func update(people: [Person], me: PersonID?) {
        let assigned = assign(people, me: me)
        let changed = hues.withLock { current -> Bool in
            guard current != assigned else { return false }
            current = assigned
            return true
        }
        if changed { PersonColorRevision.shared.value += 1 }
    }

    /// Forgets everything, for tests.
    @MainActor
    static func reset() {
        hues.withLock { $0 = [:] }
        PersonColorRevision.shared.value += 1
    }
}

/// Views read this in their body so they redraw when hues are reassigned.
@MainActor
@Observable
final class PersonColorRevision {
    static let shared = PersonColorRevision()
    var value = 0
}
