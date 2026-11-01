import Foundation
import SpltCore

extension ExpenseFormModel {
    func load() {
        do {
            me = try services.people.me()
            switch mode {
            case .add(let groupID, let prefill):
                guard let group = try services.groups.group(id: groupID) else { return failToLoad() }
                try configure(group: group, extra: [])
                applyDefaults()
                if let prefill { apply(prefill) }
            case .edit(let id):
                guard let expense = try services.expenses.expense(id: id),
                      let groupID = expense.groupID,
                      let group = try services.groups.group(id: groupID) else { return failToLoad() }
                try configure(group: group, extra: Array(expense.participants))
                let details = try services.expenses.details(id: id)
                original = expense
                originalExtras = details?.extras ?? ExpenseExtras()
                populate(from: expense)
                receipt = ReceiptAttachment(storedFileName: originalExtras.receiptFileName)
            case .editRecurring(let template):
                guard let groupID = template.groupID, let group = try services.groups.group(id: groupID) else {
                    return failToLoad()
                }
                try configure(group: group, extra: Array(template.payers.keys) + Array(template.split.participants))
                self.template = template
                populate(from: template.expense(on: template.rule.startDate))
                date = template.rule.startDate
                repeatChoice = RepeatChoice(frequency: template.rule.frequency, endDate: template.rule.endDate)
            }
        } catch {
            failToLoad()
        }
    }

    private func failToLoad() {
        loadFailed = true
    }

    func configure(group: SplitGroup, extra: [PersonID]) throws {
        self.group = group
        let ids = group.memberIDs + extra.filter { !group.memberIDs.contains($0) }.sorted()
        members = try services.people.people(ids: ids)
        currencyCode = group.currencyCode
    }

    private func applyDefaults() {
        payer.single = me?.id ?? members.first?.id
        participants = Set(members.map(\.id))
        date = dependencies.now()
    }

    private func populate(from expense: Expense) {
        amountText = AmountInput.text(for: expense.total, locale: locale)
        currencyCode = expense.total.currencyCode
        title = expense.title
        category = expense.category
        date = expense.date
        note = expense.note
        payer = PayerState(payers: expense.payers, locale: locale)
        let inSplit = expense.split.participants
        participants = inSplit.isEmpty ? Set(members.map(\.id)) : inSplit
        split = SplitEditorState(definition: expense.split, locale: locale)
    }

    /// Fills the form from a draft handed in by the caller, such as a duplicate.
    func apply(_ draft: ExpenseDraft) {
        if !draft.title.isEmpty { title = draft.title }
        if let total = draft.total {
            currencyCode = total.currencyCode
            amountText = AmountInput.text(for: total, locale: locale)
        }
        if let date = draft.date { self.date = date }
        if let category = draft.category { self.category = category }
        if !draft.note.isEmpty { note = draft.note }
        if let repeats = draft.repeats { repeatChoice.frequency = repeats }
        if !draft.payers.isEmpty { payer = PayerState(payers: draft.payers, locale: locale) }
        if let definition = draft.split {
            let inSplit = definition.participants
            participants = inSplit.isEmpty ? participants : inSplit
            split = SplitEditorState(definition: definition, locale: locale)
        }
    }
}

extension ExpenseFormModel {
    /// Groups the expense can be added to, newest first. Empty unless adding.
    var availableGroups: [SplitGroup] {
        guard case .add = mode else { return [] }
        return (try? services.groups.groups(includeArchived: false)) ?? []
    }

    /// Moves a new expense to another group, resetting the people-based fields to that group's members.
    func switchGroup(to id: GroupID) {
        guard case .add = mode, id != group?.id,
              let next = try? services.groups.group(id: id) else { return }
        let previousCurrency = group?.currencyCode
        do {
            try configure(group: next, extra: [])
        } catch {
            return
        }
        if currencyCode != previousCurrency { currencyCode = next.currencyCode }
        participants = Set(members.map(\.id))
        payer = PayerState()
        payer.single = members.contains { $0.id == me?.id } ? me?.id : members.first?.id
        split = SplitEditorState()
    }

    static let lastGroupKey = "expenses.lastGroupID"
}
