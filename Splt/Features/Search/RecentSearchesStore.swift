import Foundation

/// The last few searches, kept on this device.
struct RecentSearchesStore {
    static let limit = 8
    private static let key = "search.recent"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var queries: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    func add(_ query: String) {
        let trimmed = query.tidied
        guard trimmed.count >= 2 else { return }
        var list = queries.filter { $0.compare(trimmed, options: .caseInsensitive) != .orderedSame }
        list.insert(trimmed, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
