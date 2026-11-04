import Foundation
import Observation
import SpltCore

/// Adds people to your friends: by name, from Contacts, or by accepting an invite.
@MainActor
@Observable
final class AddFriendModel {
    enum Result: Equatable {
        case created(Person)
        /// A friend with that name already exists, so nobody new was added.
        case existing(Person)

        var person: Person {
            switch self {
            case .created(let person), .existing(let person): person
            }
        }
    }

    enum Failure: Error, Equatable {
        case emptyName
        case yourself
        case storage
    }

    var name = ""
    /// What the invite says about you. Remembered on this device.
    var inviteName: String {
        didSet { defaults.set(inviteName, forKey: Self.inviteNameKey) }
    }
    var errorMessage: String?

    private(set) var me: Person?

    static let inviteNameKey = "friends.inviteName"

    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private let defaults: UserDefaults

    init(services: DataServices, defaults: UserDefaults = .standard) {
        people = services.people
        self.defaults = defaults
        let me = try? services.people.me()
        self.me = me
        let saved = defaults.string(forKey: Self.inviteNameKey) ?? ""
        let fallback = me.map(\.name).flatMap { $0 == String(localized: "You") ? nil : $0 } ?? ""
        inviteName = saved.isEmpty ? fallback : saved
    }

    var canAddByName: Bool { !name.tidied.isEmpty }

    /// The invite to share, once you have said what to call yourself.
    var myInvite: FriendInvite? {
        let trimmed = inviteName.tidied
        guard !trimmed.isEmpty else { return nil }
        return FriendInvite(name: trimmed, personID: me?.id.rawValue)
    }

    // MARK: Adding

    @discardableResult
    func addByName() -> Result? {
        do {
            let result = try add(name: name, contactHint: nil, kind: .placeholder)
            name = ""
            return result
        } catch {
            errorMessage = message(for: error)
            return nil
        }
    }

    func add(contacts: [MemberDraft]) -> [Result] {
        var results: [Result] = []
        for contact in contacts {
            if let existing = contact.existingID, let person = try? people.person(id: existing) {
                results.append(.existing(person))
            } else if let result = try? add(name: contact.name, contactHint: contact.contactHint, kind: .placeholder) {
                results.append(result)
            }
        }
        return results
    }

    func accept(_ invite: FriendInvite) -> Result? {
        do {
            if let id = invite.personID {
                if id == me?.id.rawValue { throw Failure.yourself }
                if let known = try people.person(id: PersonID(rawValue: id)) { return .existing(known) }
            } else if let match = try people.friends().first(where: { Self.sameName($0.name, invite.name) }) {
                return .existing(match)
            }
            let person = Person(
                id: invite.personID.map { PersonID(rawValue: $0) } ?? PersonID(),
                name: invite.name, kind: .friend
            )
            try people.add(person)
            return .created(person)
        } catch {
            errorMessage = message(for: error)
            return nil
        }
    }

    private func add(name: String, contactHint: String?, kind: PersonKind) throws -> Result {
        let tidy = name.tidied
        guard !tidy.isEmpty else { throw Failure.emptyName }
        if let match = try people.friends().first(where: { Self.sameName($0.name, tidy) }) {
            return .existing(match)
        }
        let person = Person(name: tidy, contactHint: contactHint, kind: kind)
        try people.add(person)
        return .created(person)
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func message(for error: any Error) -> String {
        switch error as? Failure {
        case .emptyName: String(localized: "Enter a name first.")
        case .yourself: String(localized: "That invite is from you.")
        default: String(localized: "Something went wrong. Please try again.")
        }
    }
}
