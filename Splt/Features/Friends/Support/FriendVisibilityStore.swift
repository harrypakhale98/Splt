import Foundation
import SpltCore

/// People you chose to hide or block on this device. Nothing here is shared or synced.
///
/// Hidden people stay out of the Friends list but can still be found with search. Blocked people
/// are also left out of search, reminders and Spotlight. Neither changes any balance.
struct FriendVisibilityStore {
    enum State: String, Sendable {
        case hidden
        case blocked
    }

    private static let key = "friends.visibility"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var table: [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func state(of id: PersonID) -> State? {
        table[id.description].flatMap(State.init(rawValue:))
    }

    func set(_ state: State?, for id: PersonID) {
        var copy = table
        copy[id.description] = state?.rawValue
        defaults.set(copy, forKey: Self.key)
    }

    func ids(in state: State) -> Set<PersonID> {
        Set(table.compactMap { key, value in
            value == state.rawValue ? PersonID(uuidString: key) : nil
        })
    }

    /// Everyone who is kept out of the Friends list.
    var hiddenOrBlocked: Set<PersonID> {
        Set(table.keys.compactMap(PersonID.init(uuidString:)))
    }
}
