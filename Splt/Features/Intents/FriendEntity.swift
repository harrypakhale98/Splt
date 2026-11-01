import AppIntents
import CoreSpotlight
import Foundation
import SpltCore

/// A friend, as Siri, Shortcuts and Spotlight know them.
struct FriendEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Friend")
    static let defaultQuery = FriendEntityQuery()

    var id: UUID

    @Property(title: "Name")
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Splt friend")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = name
        attributes.displayName = name
        attributes.contentDescription = String(localized: "Splt friend")
        attributes.keywords = [name, "Splt", "friend"]
        return attributes
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ person: Person) {
        self.init(id: person.id.rawValue, name: person.name)
    }
}

struct FriendEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [FriendEntity] {
        let wanted = Set(identifiers)
        return IntentFriends.all().filter { wanted.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [FriendEntity] {
        IntentFriends.all().filter {
            $0.name.range(of: string, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [FriendEntity] {
        IntentFriends.all()
    }
}

/// The friends that intents may offer: everyone except you and people you blocked.
@MainActor
enum IntentFriends {
    static func all(services: DataServices? = IntentServices.shared.live(), visibility: FriendVisibilityStore = FriendVisibilityStore()) -> [FriendEntity] {
        guard let services else { return [] }
        let blocked = visibility.ids(in: .blocked)
        return ((try? services.people.friends()) ?? []).filter { !blocked.contains($0.id) }.map(FriendEntity.init)
    }
}
