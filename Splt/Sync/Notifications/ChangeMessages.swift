import Foundation
import SpltCore

/// Turns activity entries that arrived from other people into short, friendly sentences.
enum ChangeMessages {
    /// What a message needs to know about the world, so it can be built without a store.
    struct Names {
        var me: PersonID?
        var person: (PersonID) -> String?
        var group: (GroupID) -> String?
    }

    static let freshnessWindow: TimeInterval = 60 * 60
    static let individualLimit = 3

    static func contents(
        for activities: [SyncPayload], names: Names, now: Date
    ) -> [LocalNotificationContent] {
        let items = activities
            .compactMap { message(for: $0, names: names, now: now) }
            .sorted { $0.date < $1.date }
        guard items.count > individualLimit else {
            return items.map(\.content)
        }
        let body = String(localized: "\(items.count) new updates in your groups.")
        return [LocalNotificationContent(
            identifier: "splt.summary.\(items.last?.content.identifier ?? "")", title: "Splt", body: body
        )]
    }

    private struct Item {
        var content: LocalNotificationContent
        var date: Date
    }

    private static func message(for payload: SyncPayload, names: Names, now: Date) -> Item? {
        guard payload.recordType == .activity,
              let created = payload.fields.date("createdAt"),
              now.timeIntervalSince(created) <= freshnessWindow,
              let actor = payload.fields.uuid("actorID").map(PersonID.init(rawValue:)),
              actor != names.me,
              let actorName = names.person(actor),
              let data = payload.fields.data("event"),
              let event = try? RecordCoding.decode(ActivityEvent.self, from: data) else {
            return nil
        }
        let groupName = payload.fields.uuid("groupID").flatMap { names.group(GroupID(rawValue: $0)) }
        guard let body = sentence(for: event, actor: actorName, actorID: actor, group: groupName, names: names) else { return nil }
        return Item(
            content: LocalNotificationContent(identifier: "splt.activity.\(payload.recordName)", title: "Splt", body: body),
            date: created
        )
    }

    private static func sentence(
        for event: ActivityEvent, actor: String, actorID: PersonID, group: String?, names: Names
    ) -> String? {
        let place = group
        switch event {
        case .expenseAdded(let expense):
            return inGroup(String(localized: "\(actor) added \(expense.title)"), place)
        case .expenseEdited(let expense):
            return inGroup(String(localized: "\(actor) edited \(expense.title)"), place)
        case .expenseDeleted(let expense):
            return inGroup(String(localized: "\(actor) deleted \(expense.title)"), place)
        case .expenseRestored(let expense):
            return inGroup(String(localized: "\(actor) restored \(expense.title)"), place)
        case .paymentRecorded:
            return inGroup(String(localized: "\(actor) recorded a payment"), place)
        case .paymentUndone:
            return inGroup(String(localized: "\(actor) undid a payment"), place)
        case .commentAdded(let expense, _):
            if let expense {
                return inGroup(String(localized: "\(actor) commented on \(expense.title)"), place)
            }
            return inGroup(String(localized: "\(actor) left a comment"), place)
        case .memberAdded(let person):
            // someone who adds themselves joined, as GroupActivityText says it too
            if person == actorID {
                guard let place, !place.isEmpty else { return String(localized: "\(actor) joined the group") }
                return String(localized: "\(actor) joined \(place)")
            }
            return inGroup(String(localized: "\(actor) added \(member(person, names))"), place)
        case .memberRemoved(let person):
            if person == actorID {
                guard let place, !place.isEmpty else { return String(localized: "\(actor) left the group") }
                return String(localized: "\(actor) left \(place)")
            }
            return inGroup(String(localized: "\(actor) removed \(member(person, names))"), place)
        case .groupRenamed(_, let to):
            return String(localized: "\(actor) renamed the group to \(to)")
        case .groupArchived:
            return inGroup(String(localized: "\(actor) archived the group"), place)
        case .groupRestored:
            return inGroup(String(localized: "\(actor) restored the group"), place)
        case .expensesImported(let expenses, _):
            return inGroup(String(localized: "\(actor) imported \(expenses) expenses"), place)
        case .groupCreated:
            return nil
        }
    }

    private static func member(_ person: PersonID, _ names: Names) -> String {
        if person == names.me { return String(localized: "you") }
        return names.person(person) ?? String(localized: "someone")
    }

    private static func inGroup(_ sentence: String, _ group: String?) -> String {
        guard let group, !group.isEmpty else { return sentence }
        return String(localized: "\(sentence) in \(group)")
    }
}
