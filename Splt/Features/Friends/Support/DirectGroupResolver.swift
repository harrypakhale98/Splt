import Foundation
import SpltCore

/// Finds or creates the hidden two person group that holds expenses between you and one friend
/// outside any shared group.
@MainActor
enum DirectGroupResolver {
    static func group(
        with friend: PersonID,
        services: DataServices,
        currencyCode: String = defaultCurrencyCode()
    ) throws -> GroupID {
        let me = try services.people.me() ?? services.people.ensureMe(name: String(localized: "You"))
        let pair: Set<PersonID> = [me.id, friend]
        let existing = try services.groups.groups(includeArchived: true)
            .first { $0.kind == .friend && Set($0.memberIDs) == pair }
        if let existing { return existing.id }
        let name = try services.people.person(id: friend)?.name ?? String(localized: "Friend")
        let group = SplitGroup(
            name: name, symbol: "person.fill", currencyCode: currencyCode, kind: .friend, memberIDs: [me.id, friend]
        )
        try services.groups.create(group)
        return group.id
    }

    static func defaultCurrencyCode(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: Preferences.Key.defaultCurrency) ?? Preferences.systemCurrencyCode
    }
}
