import Foundation
import Observation
import SpltCore

/// Builds an invite made for one person who was added by name: the group's iCloud invite plus who it
/// is for, on the invite page, so they see their balance before installing and join as themselves.
@MainActor
@Observable
final class InvitePersonModel {
    enum State: Equatable {
        case loading
        /// The group is shared and only invited people can join. Nothing was changed.
        case inviteOnly
        case ready(URL)
        /// iCloud is off, so there is no invite anyone else can open.
        case needsICloud
        case failed(String)
    }

    let groupID: GroupID
    let person: Person
    private(set) var groupName = ""
    private(set) var state: State = .loading

    @ObservationIgnored private let services: DataServices
    @ObservationIgnored private let now: () -> Date

    init(groupID: GroupID, person: Person, services: DataServices, now: @escaping () -> Date = Date.init) {
        self.groupID = groupID
        self.person = person
        self.services = services
        self.now = now
        groupName = (try? services.groups.group(id: groupID))?.name ?? ""
    }

    var firstName: String { ReminderMessage.firstName(person.name) }

    /// The words sent with the link. The link goes after them.
    var message: String {
        String(localized: "Hi \(firstName), I've added you to \(groupName) on Splt. Join to see what you owe and add expenses too.")
    }

    func load(using sharing: any GroupSharing) async {
        do {
            if try await sharing.isInviteOnly(groupID: groupID) {
                state = .inviteOnly
            } else {
                state = try await link(sharing: sharing)
            }
        } catch {
            state = .failed(SyncFailure.message(for: error))
        }
    }

    /// The owner asked for a link anyone can use, so the share is opened and the invite made.
    func openToAnyone(using sharing: any GroupSharing) async {
        state = .loading
        do {
            state = try await link(sharing: sharing)
        } catch {
            state = .failed(SyncFailure.message(for: error))
        }
    }

    private func link(sharing: any GroupSharing) async throws -> State {
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
        let snapshot = BalanceSnapshot(
            group: group,
            me: try services.people.me()?.id,
            people: Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            expenses: try services.expenses.expenses(in: groupID),
            balances: try? services.groups.balances(for: groupID),
            includesExpenses: true,
            now: now(),
            invite: (shareURL, person.id)
        )
        return .ready(try BalanceLink.url(for: snapshot))
    }

    static let sampleShareURL = "https://www.icloud.com/share/0SampleInviteForTheSampleTrip"
}
