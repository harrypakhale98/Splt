import Foundation
import Observation
import SpltCore

/// The state behind "Join <group>", shown right after joining from an invite made for someone added
/// by name. Choosing that person moves everything added for them over to you, the way Merge does.
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

    init(claim: JoinClaim, services: DataServices, merger: (any PlaceholderMerging)? = nil) {
        self.services = services
        self.merger = merger ?? LivePlaceholderMerger(services: services)
        let group = try? services.groups.group(id: claim.group)
        groupName = group?.name ?? ""
        let members = (try? services.people.people(ids: group?.memberIDs ?? [])) ?? []
        let waiting = members.filter(\.isPlaceholder)
        invited = waiting.first { $0.id == claim.person }
        others = waiting.filter { $0.id != claim.person }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
