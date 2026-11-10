import AppIntents
import Foundation
import SpltCore

/// A group, as Siri and Shortcuts know it.
struct GroupEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Group")
    static let defaultQuery = GroupEntityQuery()

    var id: UUID

    @Property(title: "Name")
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Splt group")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ group: SplitGroup) {
        self.init(id: group.id.rawValue, name: group.name)
    }
}

struct GroupEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [GroupEntity] {
        let wanted = Set(identifiers)
        return IntentGroups.all().filter { wanted.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [GroupEntity] {
        IntentGroups.all().filter {
            $0.name.range(of: string, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [GroupEntity] {
        IntentGroups.all()
    }
}

/// Active groups that people made, without the hidden two person groups behind friends.
@MainActor
enum IntentGroups {
    static func all(services: DataServices? = IntentServices.shared.live(), left: LeftGroupsStore = LeftGroupsStore()) -> [GroupEntity] {
        guard let services else { return [] }
        return ((try? services.groups.groups(includeArchived: false)) ?? [])
            .filter { $0.kind != .friend && !left.contains($0.id) }
            .map(GroupEntity.init)
    }
}
