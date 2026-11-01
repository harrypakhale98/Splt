import Foundation
import SpltCore

/// Groups this device left. They stay in the shared data for the people still in them, so the list
/// keeps its own record of which ones to hide.
struct LeftGroupsStore {
    private static let key = "groups.left"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var ids: Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func contains(_ id: GroupID) -> Bool {
        ids.contains(id.description)
    }

    func insert(_ id: GroupID) {
        defaults.set(ids.union([id.description]).sorted(), forKey: Self.key)
    }

    func remove(_ id: GroupID) {
        defaults.set(ids.subtracting([id.description]).sorted(), forKey: Self.key)
    }
}
