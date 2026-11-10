import Foundation
import Observation
import SpltCore
import SwiftData

/// One person's line on the detail screen, with a sentence VoiceOver can read as is.
struct ShareLine: Identifiable, Equatable {
    var person: Person
    var name: String
    var share: Money
    var breakdown: ShareBreakdown?
    var isYou = false
    var id: PersonID { person.id }

    func spokenText(locale: Locale) -> String {
        func amount(_ money: Money) -> String { MoneyFormatting.magnitudeString(money, locale: locale) }
        var text: String
        if share.isNegative {
            text = isYou
                ? String(localized: "You get back \(amount(share))")
                : String(localized: "\(name) gets back \(amount(share))")
        } else {
            text = isYou
                ? String(localized: "You owe \(amount(share))")
                : String(localized: "\(name) owes \(amount(share))")
        }
        if let breakdown {
            var parts = [String(localized: "items \(amount(breakdown.items))")]
            if !breakdown.tax.isZero { parts.append(String(localized: "tax \(amount(breakdown.tax))")) }
            if !breakdown.tip.isZero { parts.append(String(localized: "tip \(amount(breakdown.tip))")) }
            if !breakdown.discount.isZero { parts.append(String(localized: "discount \(amount(breakdown.discount))")) }
            text += ": " + parts.formatted(.list(type: .and))
        }
        return text
    }
}

@MainActor
@Observable
final class ExpenseDetailModel {
    let expenseID: ExpenseID
    let currentLocale: Locale
    @ObservationIgnored let services: DataServices
    @ObservationIgnored private var observer: ContainerChangeObserver?

    private(set) var expense: Expense?
    private(set) var details: ExpenseDetails?
    private(set) var group: SplitGroup?
    private(set) var me: Person?
    private(set) var people: [PersonID: Person] = [:]
    private(set) var comments: [ExpenseComment] = []
    private(set) var shareLines: [ShareLine] = []
    private(set) var payerLines: [(person: Person, name: String, amount: Money)] = []
    private(set) var failed = false
    private(set) var actionError: String?

    init(expenseID: ExpenseID, services: DataServices, locale: Locale = .current) {
        self.expenseID = expenseID
        self.services = services
        self.currentLocale = locale
        observer = ContainerChangeObserver(container: services.container) { [weak self] in self?.reload() }
        reload()
    }

    var isDeleted: Bool { expense?.isDeleted ?? false }

    /// The group's members in order, so person colors never collide inside the group.
    var memberIDs: [PersonID] {
        let ordered = group?.memberIDs ?? []
        let extra = people.keys.filter { !ordered.contains($0) }.sorted()
        return ordered + extra
    }

    func name(for id: PersonID) -> String {
        if id == me?.id { return String(localized: "You") }
        return people[id]?.name ?? String(localized: "Someone")
    }

    var names: [PersonID: String] {
        Dictionary(uniqueKeysWithValues: people.keys.map { ($0, name(for: $0)) })
    }

    func reload() {
        do {
            guard let expense = try services.expenses.expense(id: expenseID) else {
                failed = true
                return
            }
            self.expense = expense
            details = try services.expenses.details(id: expenseID)
            group = try expense.groupID.flatMap { try services.groups.group(id: $0) }
            me = try services.people.me()
            let ids = Set(expense.participants).union(group?.memberIDs ?? [])
                .union(details?.history.compactMap(\.editor) ?? [])
                .union([details?.createdBy].compactMap { $0 })
            let loaded = try services.people.people(ids: ids.sorted())
            people = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            comments = try services.comments.comments(on: expenseID)
            rebuildLines(for: expense)
            failed = false
        } catch {
            failed = true
        }
    }

    /// Position in the group's member list, so the share rows follow the same order as the bar.
    private func memberOrder(_ id: PersonID) -> Int {
        memberIDs.firstIndex(of: id) ?? .max
    }

    private func rebuildLines(for expense: Expense) {
        let result = try? expense.shares()
        shareLines = (result?.shares ?? [:]).compactMap { id, share in
            people[id].map { ShareLine(
                person: $0, name: name(for: id), share: share, breakdown: result?.breakdown?[id], isYou: id == me?.id
            ) }
        }
        .sorted { memberOrder($0.id) < memberOrder($1.id) }
        payerLines = expense.payers.compactMap { id, amount in
            people[id].map { (person: $0, name: name(for: id), amount: amount) }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Actions

    func delete() {
        perform { try services.expenses.delete(id: expenseID) }
    }

    func undoDelete() {
        perform { try services.expenses.restore(id: expenseID) }
    }

    func dismissError() { actionError = nil }

    func addComment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let author = me?.id else { return }
        perform {
            try services.comments.add(ExpenseComment(
                groupID: expense?.groupID, expenseID: expenseID, authorID: author, text: trimmed,
                createdAt: services.environment.now()
            ))
        }
    }

    func toggleReaction(_ emoji: String, on comment: ExpenseComment) {
        guard let author = me?.id else { return }
        perform { try services.comments.toggleReaction(emoji, by: author, on: comment.id) }
    }

    func deleteComment(_ comment: ExpenseComment) {
        perform { try services.comments.delete(id: comment.id) }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            reload()
        } catch {
            actionError = String(localized: "That did not work. Try again.")
        }
    }

    // MARK: Derived

    var duplicateDraft: ExpenseDraft? {
        expense.map { ExpenseDraft(copying: $0) }
    }

    var shareText: String {
        guard let expense else { return "" }
        return ExpenseShareText.make(expense: expense, groupName: group?.name, names: names, locale: currentLocale)
    }

    var receiptFileName: String? { details?.extras.receiptFileName }
}
