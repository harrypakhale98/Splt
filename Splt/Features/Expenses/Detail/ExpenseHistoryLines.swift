import Foundation
import SpltCore

/// One line of an expense's history, such as "Sam changed the total from $30.00 to $36.00 · 2 Nov".
struct ExpenseHistoryLine: Identifiable, Hashable {
    var id: String
    var text: String
    /// Earlier values, for edits made before version 1.1 recorded every change.
    var detail: String?
    var date: Date
}

/// Writes the history lines of an expense. Edits from version 1.1 on come from their activity
/// entries, one line per changed field. Older edits only have the short entry kept inside the
/// expense. A 1.1 edit writes both with one id, so each edit is shown once, and an entry lost to
/// an edit made at the same time on another device still shows from its activity entry.
struct ExpenseHistoryBuilder {
    var locale: Locale
    var now: Date
    var calendar = Calendar.current
    var name: (PersonID) -> String
    var groupName: (GroupID) -> String?

    /// Newest first.
    func lines(edits: [ActivityEntry], embedded: [ExpenseEditEntry]) -> [ExpenseHistoryLine] {
        var groups: [(date: Date, lines: [ExpenseHistoryLine])] = []
        var covered = Set<UUID>()
        for entry in edits {
            let changes = entry.editChanges
            guard !changes.isEmpty else { continue }
            covered.insert(entry.id)
            let who = who(entry.actorID)
            let lines = changes.enumerated().compactMap { index, change in
                sentence(change, by: who).map {
                    ExpenseHistoryLine(id: "\(entry.id.uuidString)-\(index)", text: dated($0, entry.createdAt), date: entry.createdAt)
                }
            }
            groups.append((entry.createdAt, lines))
        }
        for entry in embedded where !covered.contains(entry.id) {
            let line = ExpenseHistoryLine(
                id: entry.id.uuidString,
                text: dated(summary(of: entry), entry.date),
                detail: Self.previousValues(of: entry, locale: locale),
                date: entry.date
            )
            groups.append((entry.date, [line]))
        }
        return groups.sorted { $0.date > $1.date }.flatMap(\.lines)
    }

    // MARK: Sentences

    /// Nil for a change the other lines of the edit already say, such as the one payer's amount
    /// following a new total.
    func sentence(_ change: ExpenseChange, by who: String) -> String? {
        let before = change.before
        let after = change.after
        switch change.field {
        case .title:
            return String(localized: "\(who) changed the title from \(quoted(before?.text)) to \(quoted(after?.text))")
        case .total:
            return String(localized: "\(who) changed the total from \(money(before?.money)) to \(money(after?.money))")
        case .date:
            return String(localized: "\(who) changed the date from \(day(before?.dateValue)) to \(day(after?.dateValue))")
        case .category:
            return String(localized: "\(who) changed the category from \(category(before?.text)) to \(category(after?.text))")
        case .payers:
            let oldPeople = before?.personIDs ?? []
            let newPeople = after?.personIDs ?? []
            guard oldPeople != newPeople else {
                return oldPeople.count > 1 ? String(localized: "\(who) changed how much each person paid") : nil
            }
            return String(localized: "\(who) changed who paid from \(payers(before)) to \(payers(after))")
        case .split:
            return splitSentence(before, after, by: who)
        case .note:
            if before == nil { return String(localized: "\(who) added a note") }
            if after == nil { return String(localized: "\(who) removed the note") }
            return String(localized: "\(who) changed the note")
        case .receipt:
            if before == nil { return String(localized: "\(who) added a receipt") }
            if after == nil { return String(localized: "\(who) removed the receipt") }
            return String(localized: "\(who) replaced the receipt")
        case .location:
            if before == nil { return String(localized: "\(who) added the location \(place(after))") }
            if after == nil { return String(localized: "\(who) removed the location") }
            return String(localized: "\(who) changed the location from \(place(before)) to \(place(after))")
        case .recurrence:
            if before == nil { return String(localized: "\(who) set it to repeat \(repeats(after))") }
            if after == nil { return String(localized: "\(who) stopped it repeating") }
            return String(localized: "\(who) changed the repeat from \(repeats(before)) to \(repeats(after))")
        case .group:
            let from = before?.id.flatMap { groupName(GroupID(rawValue: $0)) }
            let to = after?.id.flatMap { groupName(GroupID(rawValue: $0)) }
            if let from, let to { return String(localized: "\(who) moved it from \(from) to \(to)") }
            if let to { return String(localized: "\(who) moved it to \(to)") }
            return String(localized: "\(who) moved it to another group")
        }
    }

    private func splitSentence(_ before: ExpenseChangeValue?, _ after: ExpenseChangeValue?, by who: String) -> String {
        let oldKind = before?.text.flatMap(SplitMethod.init(kindName:))
        let newKind = after?.text.flatMap(SplitMethod.init(kindName:))
        if let oldKind, let newKind, oldKind != newKind {
            return String(localized: "\(who) changed the split from \(oldKind.title) to \(newKind.title)")
        }
        let oldPeople = before?.personIDs ?? []
        let newPeople = after?.personIDs ?? []
        if oldPeople != newPeople, !oldPeople.isEmpty, !newPeople.isEmpty {
            return String(localized: "\(who) changed who is in the split from \(names(oldPeople)) to \(names(newPeople))")
        }
        if newKind == .itemized { return String(localized: "\(who) changed who had which items") }
        return String(localized: "\(who) changed the split")
    }

    // MARK: Values

    private func who(_ id: PersonID?) -> String {
        id.map(name) ?? String(localized: "Someone")
    }

    private func dated(_ text: String, _ date: Date) -> String {
        "\(text) · \(shortDay(date))"
    }

    private func shortDay(_ date: Date) -> String {
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        let style = sameYear ? Date.FormatStyle.dateTime.day().month() : Date.FormatStyle.dateTime.day().month().year()
        return date.formatted(style.locale(locale))
    }

    private func day(_ date: Date?) -> String {
        guard let date else { return String(localized: "no date") }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
    }

    private func quoted(_ text: String?) -> String {
        "\u{201C}\(text ?? "")\u{201D}"
    }

    private func money(_ money: Money?) -> String {
        guard let money else { return "?" }
        // a refund keeps its minus sign, or it would read as a purchase
        return MoneyFormatting.string(money, locale: locale, showsSign: money.isNegative)
    }

    private func category(_ raw: String?) -> String {
        guard let raw else { return "?" }
        return ExpenseCategory(rawValue: raw)?.title ?? raw
    }

    private func names(_ people: [PersonID]) -> String {
        people.map(name).formatted(.list(type: .and).locale(locale))
    }

    private func payers(_ value: ExpenseChangeValue?) -> String {
        guard let value else { return "?" }
        let payments = value.payments
        guard payments.count > 1 else { return names(value.personIDs) }
        return payments.map { "\(name($0.person)) (\(money($0.amount)))" }.formatted(.list(type: .and).locale(locale))
    }

    private func place(_ value: ExpenseChangeValue?) -> String {
        value?.text.map(quoted) ?? String(localized: "a pinned place")
    }

    private func repeats(_ value: ExpenseChangeValue?) -> String {
        value?.text.flatMap(RecurrenceFrequency.init(rawValue:))?.footerPhrase ?? String(localized: "on a schedule")
    }

    // MARK: Edits from before 1.1

    private func summary(of entry: ExpenseEditEntry) -> String {
        let fields = entry.changedFields.map(\.displayName).formatted(.list(type: .and).locale(locale))
        return String(localized: "\(who(entry.editor)) changed the \(fields)")
    }

    static func previousValues(of entry: ExpenseEditEntry, locale: Locale) -> String? {
        var parts: [String] = []
        if let title = entry.previousTitle { parts.append(String(localized: "Title was \(title)")) }
        if let total = entry.previousTotal {
            // a refund's old total keeps its minus sign, or it would read as a purchase
            parts.append(String(localized: "Amount was \(MoneyFormatting.string(total, locale: locale, showsSign: total.isNegative))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }
}

extension SplitMethod {
    /// The method for a split kind stored in an edit.
    init?(kindName: String) {
        switch kindName {
        case "equal": self = .equal
        case "exact": self = .exact
        case "percentages": self = .percentage
        case "shares": self = .shares
        case "adjustments": self = .adjustment
        case "itemized": self = .itemized
        default: return nil
        }
    }
}
