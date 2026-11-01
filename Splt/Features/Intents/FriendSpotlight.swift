import CoreSpotlight
import SpltCore
import SwiftUI

/// How friends appear in Spotlight and how a tapped result is turned back into a friend.
enum FriendSpotlight {
    static let domain = "com.harrypakhale.splt.friends"
    private static let prefix = "friend."

    static func identifier(for id: PersonID) -> String {
        prefix + id.description
    }

    static func personID(fromIdentifier identifier: String) -> PersonID? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return PersonID(uuidString: String(identifier.dropFirst(prefix.count)))
    }

    static func personID(from activity: NSUserActivity) -> PersonID? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return personID(fromIdentifier: identifier)
    }

    /// Friends worth finding: not you, and not people you blocked.
    static func isIndexed(_ person: Person, blocked: Set<PersonID>) -> Bool {
        !person.isMe && !blocked.contains(person.id)
    }

    static func item(for person: Person) -> CSSearchableItem {
        let entity = FriendEntity(person)
        let attributes = entity.attributeSet
        attributes.contentDescription = person.isPlaceholder
            ? String(localized: "Splt friend, not on Splt yet")
            : String(localized: "Splt friend")
        let item = CSSearchableItem(uniqueIdentifier: identifier(for: person.id), domainIdentifier: domain, attributeSet: attributes)
        item.associateAppEntity(entity, priority: 1)
        return item
    }
}

/// Where the searchable items go, so tests can watch without touching the system index.
protocol FriendSearchIndex: Sendable {
    func replaceAll(with items: [CSSearchableItem]) async throws
}

struct SystemFriendSearchIndex: FriendSearchIndex {
    func replaceAll(with items: [CSSearchableItem]) async throws {
        let index = CSSearchableIndex.default()
        try await index.deleteSearchableItems(withDomainIdentifiers: [FriendSpotlight.domain])
        guard !items.isEmpty else { return }
        try await index.indexSearchableItems(items)
    }
}

/// Keeps Spotlight in step with your friends.
struct FriendIndexer: Sendable {
    var index: any FriendSearchIndex = SystemFriendSearchIndex()

    @discardableResult
    func update(friends: [Person], blocked: Set<PersonID>) async -> Int {
        let items = friends.filter { FriendSpotlight.isIndexed($0, blocked: blocked) }.map(FriendSpotlight.item(for:))
        do {
            try await index.replaceAll(with: items)
            return items.count
        } catch {
            return 0
        }
    }
}

extension View {
    /// Keeps friends in Spotlight and opens one when its result is tapped.
    func friendSpotlight(services: DataServices?, router: Router) -> some View {
        modifier(FriendSpotlightModifier(services: services, router: router))
    }
}

private struct FriendSpotlightModifier: ViewModifier {
    let services: DataServices?
    let router: Router

    private struct Entry: Hashable {
        var id: PersonID
        var name: String
        var isPlaceholder: Bool
    }

    private var entries: [Entry] {
        (services?.friendsStore.summaries ?? []).map { Entry(id: $0.id, name: $0.person.name, isPlaceholder: $0.person.isPlaceholder) }
    }

    func body(content: Content) -> some View {
        content
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let id = FriendSpotlight.personID(from: activity) {
                    router.open(.friend(id.rawValue))
                }
            }
            .task(id: entries) {
                guard let services else { return }
                let friends = services.friendsStore.summaries.map(\.person)
                await FriendIndexer().update(friends: friends, blocked: FriendVisibilityStore().ids(in: .blocked))
            }
    }
}
