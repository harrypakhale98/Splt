import CoreSpotlight
import Foundation
import SpltCore

/// Where the searchable items go. A protocol so tests can watch without touching the system index.
protocol GroupSearchIndex: Sendable {
    func replaceAll(with items: [CSSearchableItem]) async throws
}

struct SystemGroupSearchIndex: GroupSearchIndex {
    func replaceAll(with items: [CSSearchableItem]) async throws {
        let index = CSSearchableIndex.default()
        try await index.deleteSearchableItems(withDomainIdentifiers: [GroupSpotlight.domain])
        guard !items.isEmpty else { return }
        try await index.indexSearchableItems(items)
    }
}

/// Keeps Spotlight in step with the groups in the app.
struct GroupIndexer: Sendable {
    var index: any GroupSearchIndex = SystemGroupSearchIndex()

    /// Replaces everything Splt put in Spotlight with the groups worth finding.
    @discardableResult
    func update(groups: [SplitGroup], people: [PersonID: Person]) async -> Int {
        let items = groups.filter(GroupSpotlight.isIndexed).map { group in
            GroupSpotlight.item(for: group, memberNames: group.memberIDs.compactMap { id in
                guard let person = people[id], !person.isMe else { return nil }
                return person.name
            })
        }
        do {
            try await index.replaceAll(with: items)
            return items.count
        } catch {
            return 0
        }
    }
}
