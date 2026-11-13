import Foundation
import Observation
import SpltCore

/// Reads a reply from a balance link and turns it into the expense or payment it asks for, with the
/// group's real people, so the review sheet can show it before anything is saved.
@MainActor
@Observable
final class ReplyReviewModel {
    /// One person's part of the proposed expense.
    struct ShareLine: Equatable, Identifiable {
        var person: Person
        var amount: Money
        var id: PersonID { person.id }
    }

    /// What the reply proposes, in the group's own terms.
    struct Proposal: Equatable {
        enum Item: Equatable {
            /// Shares in the group's member order.
            case expense(Expense, payer: Person, shares: [ShareLine])
            case payment(Payment, from: Person, to: Person)
        }

        var group: SplitGroup
        var author: Person
        /// You on this phone, so lines can say "You" as the rest of the app does.
        var me: PersonID?
        var item: Item
        var sentAt: Date

        var groupName: String { SettleLeg.displayName(of: group) }

        /// A person's name, or "You".
        func name(of person: Person) -> String {
            person.id == me ? String(localized: "You") : person.name
        }
    }

    /// Why a reply can't be added.
    enum Problem: Equatable {
        /// Cut short, or not a reply at all.
        case unreadable
        case newerVersion
        /// Its code isn't one this phone made, or it has expired.
        case otherPhone(groupName: String)
        case groupMissing(groupName: String)
        /// It uses a number the balance link never gave anyone.
        case unknownPerson
        case personMissing(name: String, groupName: String)
        case personLeft(name: String, groupName: String)
        case cannotSplit
    }

    enum State: Equatable {
        case ready(Proposal)
        /// Already added once, from this same link.
        case alreadyAdded(groupName: String, group: GroupID)
        case problem(Problem)
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
        token = (try? BalanceReply(fragment: fragment))?.token
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
            return .problem(.newerVersion)
        } catch {
            return .problem(.unreadable)
        }
        guard let entry = store.entry(for: reply.token) else {
            return .problem(.otherPhone(groupName: reply.groupName))
        }
        guard let group = try? services.groups.group(id: GroupID(rawValue: entry.group)) else {
            return .problem(.groupMissing(groupName: reply.groupName))
        }
        let groupName = SettleLeg.displayName(of: group)
        if store.wasAdded(BalanceReply.id(ofFragment: fragment), token: reply.token) {
            return .alreadyAdded(groupName: groupName, group: group.id)
        }

        // the link's numbers, back to the people they stood for
        guard reply.people.allSatisfy(entry.people.indices.contains) else { return .problem(.unknownPerson) }
        let ids = entry.people.map { PersonID(rawValue: $0) }
        let found = (try? services.people.people(ids: ids)) ?? []
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let members = Set(group.memberIDs)
        var people: [Int: Person] = [:]
        for index in reply.people.sorted() {
            guard let person = byID[ids[index]] else {
                let name = reply.names[index] ?? String(localized: "Someone")
                return .problem(.personMissing(name: name, groupName: groupName))
            }
            people[index] = person
        }
        // every number the reply uses was looked up above
        guard let author = people[reply.author] else { return .problem(.unknownPerson) }
        let me = (try? services.people.me())?.id
        let note = String(localized: "Sent by \(author.name) from a balance link")

        switch reply.kind {
        case .expense(let title, _, let payerIndex, let participantIndexes):
            guard let payer = people[payerIndex] else { return .problem(.unknownPerson) }
            let participants = participantIndexes.compactMap { people[$0] }
            if let gone = ([payer] + participants).first(where: { !members.contains($0.id) }) {
                return .problem(.personLeft(name: gone.name, groupName: groupName))
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
            guard let split = try? expense.shares().shares else { return .problem(.cannotSplit) }
            let order = Dictionary(group.memberIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            let shares = participants
                .compactMap { person in split[person.id].map { ShareLine(person: person, amount: $0) } }
                .sorted { (order[$0.person.id] ?? .max) < (order[$1.person.id] ?? .max) }
            return .ready(Proposal(
                group: group, author: author, me: me,
                item: .expense(expense, payer: payer, shares: shares),
                sentAt: reply.createdAt
            ))
        case .payment(let fromIndex, let toIndex):
            guard let from = people[fromIndex], let to = people[toIndex] else { return .problem(.unknownPerson) }
            let payment = Payment(
                groupID: group.id, payer: from.id, receiver: to.id, amount: reply.money,
                // when they said they paid, never a time still to come
                date: min(reply.createdAt, now), note: note
            )
            return .ready(Proposal(
                group: group, author: author, me: me,
                item: .payment(payment, from: from, to: to),
                sentAt: reply.createdAt
            ))
        }
    }
}
