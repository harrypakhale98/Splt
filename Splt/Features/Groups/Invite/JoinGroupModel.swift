import Foundation
import Observation
import SpltCore

/// The state behind "Join <group>", shown right after joining from an invite page. Choosing someone
/// added by name moves everything added for them over to you, the way Merge does. An invite made for one
/// person puts them first; one for the whole group chat lists everyone still waiting.
@MainActor
@Observable
final class JoinGroupModel {
    let groupName: String
    /// The person the invite was made for, while they are still waiting to be claimed.
    private(set) var invited: Person?
    /// What the invited person owes or is owed in this group, in one line.
    private(set) var invitedLine: String?
    /// Everyone else in the group who isn't on Splt yet.
    private(set) var others: [Person] = []
    private(set) var didJoin = false
    var errorMessage: String?

    @ObservationIgnored private let services: DataServices
    @ObservationIgnored private let merger: any PlaceholderMerging
    @ObservationIgnored private let profile: AccountProfile

    init(
        claim: JoinClaim, services: DataServices, merger: (any PlaceholderMerging)? = nil,
        profile: AccountProfile = .shared
    ) {
        self.services = services
        self.merger = merger ?? LivePlaceholderMerger(services: services)
        self.profile = profile
        let group = try? services.groups.group(id: claim.group)
        groupName = group?.name ?? ""
        let members = (try? services.people.people(ids: group?.memberIDs ?? [])) ?? []
        let waiting = members.filter(\.isPlaceholder)
        invited = claim.person.flatMap { person in waiting.first { $0.id == person } }
        others = waiting.filter { $0.id != invited?.id }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let invited {
            let names = Dictionary(members.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            let debts = (try? services.groups.balances(for: claim.group).suggestedSettlements) ?? []
            invitedLine = Self.line(for: invited.id, debts: debts, names: names)
        }
    }

    /// Nobody here is waiting to be claimed, so there is nothing to ask.
    var isEmpty: Bool { invited == nil && others.isEmpty }

    func join(as person: Person) {
        do {
            guard let me = try services.people.me() else {
                errorMessage = String(localized: "Something went wrong. Please try again.")
                return
            }
            try merger.merge(person.id, into: me.id)
            // someone who never chose a name keeps the one the group knows them by, not "You"
            if !profile.hasChosenName || me.name == String(localized: "You") {
                try? profile.takeInvitedName(person.name, people: services.people)
            }
            didJoin = true
            errorMessage = nil
        } catch let error as MergeError {
            errorMessage = error.message
        } catch {
            errorMessage = String(localized: "Something went wrong. Please try again.")
        }
    }

    static func line(for person: PersonID, debts: [Debt], names: [PersonID: String]) -> String {
        let owes = debts.filter { $0.debtor == person }
        let owed = debts.filter { $0.creditor == person }
        if owes.count == 1, let debt = owes.first {
            return String(localized: "You owe \(names[debt.creditor] ?? "") \(debt.amount.formatted())")
        }
        if owes.count > 1 { return String(localized: "You owe \(owes.count) people") }
        if owed.count == 1, let debt = owed.first {
            return String(localized: "\(names[debt.debtor] ?? "") owes you \(debt.amount.formatted())")
        }
        if owed.count > 1 { return String(localized: "\(owed.count) people owe you") }
        return String(localized: "Settled up")
    }
}
