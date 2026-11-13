import Foundation
import Observation
import SpltCore

/// Reads a reply from a balance link and turns it into the expense or payment it asks for, with the
/// group's real people, so the review sheet can show it before anything is saved.
@MainActor
@Observable
final class ReplyReviewModel {
    /// What the reply proposes, in the group's own terms.
    struct Proposal: Equatable {
        enum Item: Equatable {
            case expense(Expense, payer: Person, participants: [Person])
            case payment(Payment, from: Person, to: Person)
        }

        var group: SplitGroup
        var author: Person
        var item: Item
        var sentAt: Date

        var groupName: String { SettleLeg.displayName(of: group) }
    }

    enum State: Equatable {
        case ready(Proposal)
        /// Already added once, from this same link.
        case alreadyAdded(groupName: String, group: GroupID)
        /// Can't be added; the text says why.
        case problem(title: String, message: String)
    }

    private(set) var state: State
    var errorMessage: String?

    private let services: DataServices
    private let store: BalanceReplyStore
    private let replyID: String
    private let token: String?

    init(fragment: String, services: DataServices, store: BalanceReplyStore = BalanceReplyStore(), now: Date = Date()) {
        self.services = services
        self.store = store
        replyID = BalanceReply.id(ofFragment: fragment)
        let reply = try? BalanceReply(fragment: fragment)
        token = reply?.token
        state = Self.resolve(fragment: fragment, services: services, store: store, now: now)
    }

    /// Saves what the reply proposes. Returns the group it went into, or nil if saving failed.
    func add() -> GroupID? {
        guard case .ready(let proposal) = state, let token else { return nil }
        do {
            switch proposal.item {
            case .expense(let expense, _, _): try services.expenses.add(expense)
            case .payment(let payment, _, _): try services.payments.record(payment)
            }
        } catch {
            errorMessage = String(localized: "It couldn't be saved. Try again.")
            return nil
        }
        store.markAdded(replyID, token: token)
        state = .alreadyAdded(groupName: proposal.groupName, group: proposal.group.id)
        return proposal.group.id
    }

    // MARK: Reading

    private static func resolve(fragment: String, services: DataServices, store: BalanceReplyStore, now: Date) -> State {
        let reply: BalanceReply
        do {
            reply = try BalanceReply(fragment: fragment)
        } catch BalanceReply.FormatError.unsupportedVersion {
            return .problem(
                title: String(localized: "Update Splt"),
                message: String(localized: "This was sent from a newer balance page than this version of Splt reads. Update Splt and open the link again.")
            )
        } catch {
            return .problem(
                title: String(localized: "This Link Doesn't Open"),
                message: String(localized: "It may have been cut short when it was copied. Ask for it to be sent again.")
            )
        }
        guard let entry = store.entry(for: reply.token) else {
            return .problem(
                title: String(localized: "Open This on the Other iPhone"),
                message: String(localized: "This answers a balance link for \(reply.groupName) that was shared from another iPhone, or more than six months ago. Only the iPhone that shared the link can add it.")
            )
        }
        let groupID = GroupID(rawValue: entry.group)
        guard let group = try? services.groups.group(id: groupID) else {
            return .problem(
                title: String(localized: "Group Not Found"),
                message: String(localized: "\(reply.groupName) isn't on this iPhone anymore.")
            )
        }
        let groupName = SettleLeg.displayName(of: group)
        if store.wasAdded(BalanceReply.id(ofFragment: fragment), token: reply.token) {
            return .alreadyAdded(groupName: groupName, group: group.id)
        }

        // the link's numbers, back to the people they stood for
        let unknownPerson = State.problem(
            title: String(localized: "This Link Doesn't Open"),
            message: String(localized: "It names someone the balance link didn't. Ask for it to be sent again.")
        )
        guard reply.people.allSatisfy(entry.people.indices.contains) else { return unknownPerson }
        let ids = entry.people.map { PersonID(rawValue: $0) }
        let found = (try? services.people.people(ids: ids)) ?? []
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let members = Set(group.memberIDs)
        var people: [Int: Person] = [:]
        for index in reply.people.sorted() {
            guard let person = byID[ids[index]] else {
                return .problem(
                    title: String(localized: "Someone Is Missing"),
                    message: String(localized: "\(reply.names[index] ?? String(localized: "Someone")) isn't in \(groupName) anymore, so this can't be added.")
                )
            }
            people[index] = person
        }
        // every number the reply uses was looked up above
        guard let author = people[reply.author] else { return unknownPerson }
        let note = String(localized: "Sent by \(author.name) from a balance link")

        switch reply.kind {
        case .expense(let title, _, let payerIndex, let participantIndexes):
            guard let payer = people[payerIndex] else { return unknownPerson }
            let participants = participantIndexes.compactMap { people[$0] }
            if let gone = ([payer] + participants).first(where: { !members.contains($0.id) }) {
                return .problem(
                    title: String(localized: "Someone Left"),
                    message: String(localized: "\(gone.name) has left \(groupName), so this expense can't be added.")
                )
            }
            let expense = Expense(
                groupID: group.id,
                title: BalanceSnapshot.clipped(title, limit: BalanceReply.titleLimit, fallback: String(localized: "Expense")),
                total: reply.money,
                date: reply.date() ?? now,
                paidBy: payer.id,
                split: .equal(participants: Set(participants.map(\.id))),
                note: note
            )
            guard (try? expense.shares()) != nil else {
                return .problem(
                    title: String(localized: "This Can't Be Split"),
                    message: String(localized: "The amount doesn't divide between these people. Ask for it to be sent again.")
                )
            }
            return .ready(Proposal(
                group: group, author: author,
                item: .expense(expense, payer: payer, participants: participants),
                sentAt: reply.createdAt
            ))
        case .payment(let fromIndex, let toIndex):
            guard let from = people[fromIndex], let to = people[toIndex] else { return unknownPerson }
            let payment = Payment(
                groupID: group.id, payer: from.id, receiver: to.id, amount: reply.money,
                // when they said they paid, never a time still to come
                date: min(reply.createdAt, now), note: note
            )
            return .ready(Proposal(
                group: group, author: author,
                item: .payment(payment, from: from, to: to),
                sentAt: reply.createdAt
            ))
        }
    }
}
