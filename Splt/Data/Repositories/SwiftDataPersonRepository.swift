import Foundation
import SpltCore
import SwiftData

@MainActor
final class SwiftDataPersonRepository: PersonRepository {
    private let env: RepositoryContext

    init(_ env: RepositoryContext) {
        self.env = env
    }

    func me() throws -> Person? {
        try env.currentUser().map(Person.init)
    }

    @discardableResult
    func ensureMe(name: String) throws -> Person {
        if let existing = try me() { return existing }
        let person = Person(name: name, kind: .me, createdAt: env.now())
        try add(person)
        return person
    }

    func person(id: PersonID) throws -> Person? {
        try env.personRecord(id).map(Person.init)
    }

    func people(ids: [PersonID]) throws -> [Person] {
        let wanted = Set(ids.map(\.rawValue))
        let descriptor = FetchDescriptor<PersonRecord>(predicate: #Predicate { $0.deletedAt == nil })
        let byID = Dictionary(
            try env.context.fetch(descriptor).filter { wanted.contains($0.id) }.map { ($0.personID, Person($0)) },
            uniquingKeysWith: { first, _ in first }
        )
        return ids.compactMap { byID[$0] }
    }

    func allPeople() throws -> [Person] {
        let descriptor = FetchDescriptor<PersonRecord>(predicate: #Predicate { $0.deletedAt == nil })
        return try env.context.fetch(descriptor).map(Person.init).sorted(by: Self.byName)
    }

    func friends() throws -> [Person] {
        try allPeople().filter { !$0.isMe }
    }

    func add(_ person: Person) throws {
        let record = PersonRecord(person)
        env.context.insert(record)
        env.tracker.recordEdit(record)
        try env.save()
    }

    func update(_ person: Person) throws {
        guard let record = try env.personRecord(person.id) else { throw DataError.notFound("person \(person.id)") }
        record.update(from: person)
        env.tracker.recordEdit(record)
        try env.save()
    }

    func claim(_ id: PersonID, cloudUserID: String) throws {
        guard let record = try env.personRecord(id) else { throw DataError.notFound("person \(id)") }
        record.claimedByCloudUserID = cloudUserID
        if record.kind == .placeholder {
            record.kind = .friend
        }
        env.tracker.recordEdit(record)
        try env.save()
    }

    func delete(id: PersonID) throws {
        guard let record = try env.personRecord(id) else { return }
        env.tracker.tombstone(record)
        try env.save()
    }

    func friendBalance(with friend: PersonID) throws -> FriendBalance {
        try friendBalances().first { $0.friendID == friend } ?? FriendBalance(friendID: friend, total: [], byGroup: [])
    }

    func friendBalances() throws -> [FriendBalance] {
        guard let me = try env.currentUser()?.personID else { return [] }
        var amounts: [PersonID: [GroupID: [Money]]] = [:]
        for group in try env.allGroups() {
            let ledger = try env.ledger(forGroup: group.id)
            for (friend, owed) in ledger.balances(with: me) {
                amounts[friend, default: [:]][group.id, default: []] += owed
            }
        }
        let names = Dictionary(
            try allPeople().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        return amounts.keys
            .sorted { (names[$0] ?? "", $0) < (names[$1] ?? "", $1) }
            .map { friend in
                let groups = amounts[friend] ?? [:]
                let byGroup = groups.keys.sorted().compactMap { groupID -> GroupAmounts? in
                    let summed = MoneyTotals.sum(groups[groupID] ?? [])
                    return summed.isEmpty ? nil : GroupAmounts(groupID: groupID, amounts: summed)
                }
                return FriendBalance(
                    friendID: friend, total: MoneyTotals.sum(byGroup.flatMap(\.amounts)), byGroup: byGroup
                )
            }
    }

    private static func byName(_ lhs: Person, _ rhs: Person) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }
}
