import Foundation
import SpltCore

/// Suggests people who may be the same person as a placeholder, such as "Sam" and "Samuel Reed".
enum DuplicateFinder {
    /// Other people whose name matches the placeholder's name, closest match first.
    static func candidates(for person: Person, among others: [Person]) -> [Person] {
        let mine = words(person.name)
        guard !mine.isEmpty else { return [] }
        return others
            .filter { $0.id != person.id && !$0.isMe }
            .compactMap { other -> (Person, Int)? in
                guard let score = score(mine, words(other.name)) else { return nil }
                return (other, score)
            }
            .sorted { ($0.1, $0.0.name) < ($1.1, $1.0.name) }
            .map(\.0)
    }

    /// Lower is closer. Nil when the names do not look alike.
    private static func score(_ lhs: [String], _ rhs: [String]) -> Int? {
        guard !rhs.isEmpty else { return nil }
        if lhs == rhs { return 0 }
        if lhs.first == rhs.first { return 1 }
        if rhs.contains(lhs.first ?? ""), lhs.count == 1 { return 2 }
        if lhs.contains(rhs.first ?? ""), rhs.count == 1 { return 2 }
        guard let a = lhs.first, let b = rhs.first else { return nil }
        if min(a.count, b.count) >= 3, a.hasPrefix(b) || b.hasPrefix(a) { return 2 }
        if min(a.count, b.count) >= 4, EditDistance.between(a, b) <= 1 { return 3 }
        return nil
    }

    private static func words(_ name: String) -> [String] {
        name.foldedWords
    }
}
