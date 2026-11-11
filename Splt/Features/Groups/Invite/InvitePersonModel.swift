import Foundation
import Observation
import SpltCore

/// Who an invite is for: one person added by name, or everyone in the group still waiting to join.
enum Invitee: Identifiable, Hashable {
    case person(Person)
    case everyone

    var id: String {
        switch self {
        case .person(let person): person.id.rawValue.uuidString
        case .everyone: "everyone"
        }
    }
}

/// Builds an invite for people added by name: the group's iCloud invite plus who it is for, on the invite
/// page, so they see their balance before installing and join as themselves.
@MainActor
@Observable
final class InvitePersonModel {
    enum State: Equatable {
        case loading
        /// The group is shared and only invited people can join. Nothing was changed.
        case inviteOnly
        case ready(Links)
        /// iCloud is off, so there is no invite anyone else can open.
        case needsICloud
        case failed(String)
    }

    /// The link to send, and a shorter one without recent expenses for the QR code, which a camera reads
    /// more easily the less it holds.
    struct Links: Equatable {
        var send: URL
        var scan: URL
    }

    /// Where Send Invite goes straight to, for someone added from Contacts.
    enum Recipient: Equatable {
        case phone(String)
        case email(String)

        init?(contactHint: String?) {
            guard let hint = contactHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty else { return nil }
            if hint.contains("@") {
                self = .email(hint)
            } else if hint.filter(\.isNumber).count >= 5 {
                self = .phone(hint)
            } else {
                return nil
            }
        }

        var address: String {
            switch self {
            case .phone(let number): number
            case .email(let address): address
            }
        }
    }

    let groupID: GroupID
    let invitee: Invitee
    private(set) var groupName = ""
    /// Everyone still waiting to join, for an invite to all of them.
    private(set) var waiting: [Person] = []
    private(set) var state: State = .loading

    @ObservationIgnored private let services: DataServices
    @ObservationIgnored private let now: () -> Date

    init(groupID: GroupID, invitee: Invitee, services: DataServices, now: @escaping () -> Date = Date.init) {
        self.groupID = groupID
        self.invitee = invitee
        self.services = services
        self.now = now
        let group = try? services.groups.group(id: groupID)
        groupName = group?.name ?? ""
        waiting = ((try? services.people.people(ids: group?.memberIDs ?? [])) ?? []).filter(\.isPlaceholder)
    }

    var person: Person? {
        if case .person(let person) = invitee { return person }
        return nil
    }

    var firstName: String { person.map { ReminderMessage.firstName($0.name) } ?? "" }

    var title: String {
        person == nil ? String(localized: "Invite Everyone") : String(localized: "Invite \(firstName)")
    }

    /// The words sent with the link. The link goes after them.
    var message: String {
        if person == nil {
            return String(localized: "Hi everyone, I've added you to \(groupName) on Splt. Open the link, pick your name, and you're in.")
        }
        return String(localized: "Hi \(firstName), I've added you to \(groupName) on Splt. Join to see what you owe and add expenses too.")
    }

    /// The message and the link, as Copy Link and Messages send them.
    func text(with link: URL) -> String {
        message + "\n" + link.absoluteString
    }

    var recipient: Recipient? { Recipient(contactHint: person?.contactHint) }

    func load(using sharing: any GroupSharing) async {
        do {
            if try await sharing.isInviteOnly(groupID: groupID) {
                state = .inviteOnly
            } else {
                state = try await links(sharing: sharing)
            }
        } catch {
            state = .failed(SyncFailure.message(for: error))
        }
    }

    /// The owner asked for a link anyone can use, so the share is opened and the invite made.
    func openToAnyone(using sharing: any GroupSharing) async {
        state = .loading
        do {
            state = try await links(sharing: sharing)
        } catch {
            state = .failed(SyncFailure.message(for: error))
        }
    }

    private func links(sharing: any GroupSharing) async throws -> State {
        var shareURL = try await sharing.inviteURL(for: groupID, groupName: groupName)
        if shareURL.scheme == DeepLink.scheme {
            #if DEBUG
            // the sample trip has no iCloud, so it gets a stand-in invite to show the screens with
            if ProcessInfo.processInfo.arguments.contains("-sampledata"), let sample = URL(string: Self.sampleShareURL) {
                shareURL = sample
            } else {
                return .needsICloud
            }
            #else
            return .needsICloud
            #endif
        }
        guard let group = try services.groups.group(id: groupID) else { throw DataError.notFound("group \(groupID)") }
        let people = try services.people.people(ids: group.memberIDs)
        let me = try services.people.me()?.id
        let expenses = try services.expenses.expenses(in: groupID)
        let balances = try? services.groups.balances(for: groupID)
        func link(withExpenses: Bool) throws -> URL {
            try BalanceLink.url(for: BalanceSnapshot(
                group: group,
                me: me,
                people: Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                expenses: expenses,
                balances: balances,
                includesExpenses: withExpenses,
                now: now(),
                invite: person.map { (shareURL, $0.id) },
                inviteEveryone: person == nil ? (shareURL, waiting.map(\.id)) : nil
            ))
        }
        return .ready(Links(send: try link(withExpenses: true), scan: try link(withExpenses: false)))
    }

    static let sampleShareURL = "https://www.icloud.com/share/0SampleInviteForTheSampleTrip"
}
