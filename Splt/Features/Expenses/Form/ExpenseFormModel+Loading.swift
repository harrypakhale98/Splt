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
                applyDefaultSplit(of: group)
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
        setAmount(expense.total)
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

    /// Shows a stored total. A negative one makes the form a refund, and the text keeps its size.
    private func setAmount(_ total: Money) {
        isRefund = total.isNegative
        let size = total.isNegative ? 0 &- total.minorUnits : total.minorUnits
        amountText = AmountInput.text(for: Money(minorUnits: size, currencyCode: total.currencyCode), locale: locale)
    }

    /// Fills the form from a draft handed in by the caller, such as a duplicate.
    func apply(_ draft: ExpenseDraft) {
        if !draft.title.isEmpty { title = draft.title }
        if let total = draft.total {
            currencyCode = total.currencyCode
            setAmount(total)
        }
        if let date = draft.date { self.date = date }
        if let category = draft.category { self.category = category }
        if !draft.note.isEmpty { note = draft.note }
        if let repeats = draft.repeats { repeatChoice.frequency = repeats }
        // The draft can name people who have left the group since. The form cannot show them,
        // so they must not stay in what it saves.
        let present = Set(members.map(\.id))
        let payers = draft.payers.filter { present.contains($0.key) }
        if !payers.isEmpty { payer = PayerState(payers: payers, locale: locale) }
        if let definition = draft.split {
            let inSplit = definition.participants.intersection(present)
            participants = inSplit.isEmpty ? participants : inSplit
            split = SplitEditorState(definition: definition, locale: locale)
            split.keepPeople(present)
        }
    }
}

extension ExpenseFormModel {
    /// Groups the expense can be added to, newest first. Empty unless adding.
    var availableGroups: [SplitGroup] {
        guard case .add = mode else { return [] }
        let groups = (try? services.groups.groups(includeArchived: false)) ?? []
        let left = LeftGroupsStore(defaults: dependencies.defaults)
        return groups.filter { $0.kind != .friend && !left.contains($0.id) }
    }

    /// Moves a new expense to another group, resetting the people-based fields to that group's members.
    func switchGroup(to id: GroupID) {
        guard case .add = mode, id != group?.id,
              let next = try? services.groups.group(id: id) else { return }
        // A currency picked by hand or read from a receipt stays. One that only followed the old group follows the new one.
        let chosenCurrency = currencyCode != group?.currencyCode ? currencyCode : nil
        do {
            try configure(group: next, extra: [])
        } catch {
            return
        }
        if let chosenCurrency { currencyCode = chosenCurrency }
        participants = Set(members.map(\.id))
        payer = PayerState()
        payer.single = members.contains { $0.id == me?.id } ? me?.id : members.first?.id
        // The items, tax, tip and discount belong to the bill, not to the group. Only who owes what starts over.
        split.keepPeople([])
        if split.method != .itemized { split.method = .equal }
        applyDefaultSplit(of: next)
    }

    static let lastGroupKey = "expenses.lastGroupID"
}
