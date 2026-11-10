import Foundation
import Observation
import SpltCore
import Synchronization

/// The one list of who has which hue. You get the brand teal. Everyone else is handed a hue nobody
/// present holds the first time the app sees them, in the order they were added, and keeps it from
/// then on: the list is saved, so a person synced in later with an earlier date, or a deleted
/// contact, never re-colors anyone who is already there.
enum PersonColorBook {
    /// A person's hue and when they got it. Within a group, the person who got their hue first keeps
    /// it when two members share one.
    struct Entry: Hashable, Sendable {
        var hue: Int
        var rank: Int
    }

    private static let storageKey = "PersonColorBook.v1"
    private static let stored = Mutex<[PersonID: Entry]>(load())

    static func index(for person: PersonID) -> Int? {
        stored.withLock { $0[person]?.hue }
    }

    /// The saved entries of these people, read under one lock.
    static func entries(for people: some Sequence<PersonID>) -> [PersonID: Entry] {
        stored.withLock { book in
            var result: [PersonID: Entry] = [:]
            for person in people { result[person] = book[person] }
            return result
        }
    }

    /// The hues for these people from scratch, without storing them.
    static func assign(_ people: [Person], me: PersonID?) -> [PersonID: Int] {
        assigning(people, me: me, existing: [:]).mapValues(\.hue)
    }

    /// The book after these people are seen. Everyone in `existing` keeps their hue and rank, you
    /// always have the brand hue, and newcomers take hues that nobody present holds, oldest first.
    static func assigning(_ people: [Person], me: PersonID?, existing: [PersonID: Entry]) -> [PersonID: Entry] {
        var result = existing
        if let me { result[me] = Entry(hue: PersonPalette.meIndex, rank: -1) }
        var present = Set(people.map(\.id))
        if let me { present.insert(me) }
        let reserved = Set(result.compactMap { present.contains($0.key) ? $0.value.hue : nil })
        let newcomers = people
            .filter { result[$0.id] == nil }
            .sorted { lhs, rhs in
                lhs.createdAt == rhs.createdAt ? lhs.id.description < rhs.id.description : lhs.createdAt < rhs.createdAt
            }
        let hues = PersonPalette.resolve(newcomers.map(\.id), reserved: reserved)
        var nextRank = (result.values.map(\.rank).max() ?? -1) + 1
        for person in newcomers where result[person.id] == nil {
            result[person.id] = Entry(hue: hues[person.id] ?? PersonPalette.preferredIndex(for: person.id), rank: nextRank)
            nextRank += 1
        }
        return result
    }

    /// Adds anyone new, saves the book and tells views to redraw when anything changed.
    @MainActor
    static func update(people: [Person], me: PersonID?) {
        let changed = stored.withLock { current -> [PersonID: Entry]? in
            let next = assigning(people, me: me, existing: current)
            guard next != current else { return nil }
            current = next
            return next
        }
        guard let changed else { return }
        save(changed)
        PersonColorRevision.shared.value += 1
    }

    /// Forgets everything, saved hues included, for tests.
    @MainActor
    static func reset() {
        stored.withLock { $0 = [:] }
        UserDefaults.standard.removeObject(forKey: storageKey)
        PersonColorRevision.shared.value += 1
    }

    private static func load() -> [PersonID: Entry] {
        guard let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: [Int]] else { return [:] }
        var result: [PersonID: Entry] = [:]
        for (key, pair) in saved {
            guard pair.count == 2, let uuid = UUID(uuidString: key) else { continue }
            result[PersonID(rawValue: uuid)] = Entry(hue: pair[0], rank: pair[1])
        }
        return result
    }

    private static func save(_ book: [PersonID: Entry]) {
        let plist = Dictionary(uniqueKeysWithValues: book.map { ($0.key.rawValue.uuidString, [$0.value.hue, $0.value.rank]) })
        UserDefaults.standard.set(plist, forKey: storageKey)
    }
}

/// Views read this in their body so they redraw when hues are reassigned.
@MainActor
@Observable
final class PersonColorRevision {
    static let shared = PersonColorRevision()
    var value = 0
}
