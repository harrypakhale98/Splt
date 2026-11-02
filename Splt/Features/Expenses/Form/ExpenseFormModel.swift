import Foundation
import Observation
import SpltCore

/// How often a new expense repeats, chosen in the form. Nil frequency means it does not.
struct RepeatChoice: Equatable, Sendable {
    var frequency: RecurrenceFrequency?
    var endDate: Date?
}

/// The receipt photo attached to the expense: one already stored, or a new one waiting for Save.
struct ReceiptAttachment: Equatable, Sendable {
    var storedFileName: String?
    var pendingImage: Data?

    var isEmpty: Bool { storedFileName == nil && pendingImage == nil }
}

/// What the expense form shows and edits. Views bind to the plain fields; the computed
/// properties turn them into a validated `Expense` with the SpltCore calculator.
@MainActor
@Observable
final class ExpenseFormModel {
    struct Dependencies {
        var parser: any QuickAddParsing = SmartQuickAddParser()
        var categories: any CategorySuggesting = CategorySuggester()
        var scanner: @Sendable (_ defaultCurrencyCode: String) -> any ReceiptScanning = {
            VisionReceiptScanner(defaultCurrencyCode: $0)
        }
        var receipts: ReceiptStore = .standard
        /// Nil uses the app's cached rates, `DataServices.expenseRates`.
        var rates: ExpenseRates?
        /// Looks up rates for an expense date and currency without blocking. Nil uses `DataServices.rates`.
        var rateLookup: (@Sendable (_ group: SplitGroup, _ date: Date, _ currencyCode: String) async -> ExchangeRates?)?
        var defaults: UserDefaults = .standard
        var locale: Locale = .current
        var now: @Sendable () -> Date = { Date() }
    }

    let mode: ExpenseFormMode
    let dependencies: Dependencies
    @ObservationIgnored let services: DataServices

    var group: SplitGroup?
    var members: [Person] = []
    var me: Person?
    var loadFailed = false
    /// The expense being edited, with the extras and history stored beside it.
    @ObservationIgnored var original: Expense?
    @ObservationIgnored var originalExtras = ExpenseExtras()
    @ObservationIgnored var template: RecurringExpense?

    var amountText = ""
    var currencyCode = "USD"
    var title = ""
    var category: ExpenseCategory = .general
    var date: Date
    var note = ""
    var payer = PayerState()
    var participants: Set<PersonID> = []
    var split = SplitEditorState()
    var repeatChoice = RepeatChoice()
    var receipt = ReceiptAttachment()
    private(set) var isFindingRate = false
    @ObservationIgnored private var fetchedRates: (key: String, rates: ExchangeRates?)?

    var describeText = ""
    var isReading = false
    var filledNotice: String?
    var unmatchedNames: [String] = []
    var suggestedCategory: ExpenseCategory?
    var possibleDuplicates: [Expense] = []
    var isScanning = false
    var scanNotice: String?
    var saveCount = 0
    var saveError: String?
    @ObservationIgnored private var snapshot: Snapshot?
    @ObservationIgnored var categoryTask: Task<Void, Never>?

    init(mode: ExpenseFormMode, services: DataServices, dependencies: Dependencies = Dependencies()) {
        self.mode = mode
        self.services = services
        self.dependencies = dependencies
        self.date = dependencies.now()
        load()
        snapshot = Snapshot(self)
    }

    // MARK: Derived values

    var isEditing: Bool {
        switch mode {
        case .add: false
        case .edit, .editRecurring: true
        }
    }

    var isEditingRecurring: Bool {
        if case .editRecurring = mode { return true }
        return false
    }

    var locale: Locale { dependencies.locale }
    var groupCurrencyCode: String { group?.currencyCode ?? currencyCode }

    var total: Money? {
        AmountInput.money(amountText, currencyCode: currencyCode, locale: locale, allowNegative: original?.isRefund == true)
    }

    var isDirty: Bool { snapshot.map { $0 != Snapshot(self) } ?? false }

    /// The member's name, or "You" for the person using the app.
    func displayName(for id: PersonID) -> String {
        if id == me?.id { return String(localized: "You") }
        return members.first { $0.id == id }?.name ?? String(localized: "Someone")
    }

    func person(_ id: PersonID) -> Person? { members.first { $0.id == id } }

    /// Members in display order who are in the split, for the editors.
    var participantList: [Person] { members.filter { participants.contains($0.id) } }

    /// Changes when the currency, the expense day or the group changes, to restart the rate lookup.
    var rateKey: String {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(group?.id.description ?? "")|\(currencyCode)|\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
    }

    /// The rates to convert with: the lookup for this day and currency once it has finished,
    /// until then whatever the app already holds.
    private var activeRates: ExchangeRates? {
        guard let group else { return nil }
        if let fetchedRates, fetchedRates.key == rateKey, let rates = fetchedRates.rates { return rates }
        return (dependencies.rates ?? services.expenseRates).rates(group)
    }

    /// The group amount for the typed amount, when the currencies differ and a rate is known.
    var convertedTotal: Money? {
        guard let total, let group, currencyCode != group.currencyCode, let rates = activeRates else { return nil }
        return try? rates.convert(total, to: group.currencyCode)
    }

    /// True when the expense is in another currency but no rate is known to show its value.
    var lacksRate: Bool {
        guard total != nil, let group, currencyCode != group.currencyCode, !isFindingRate else { return false }
        return convertedTotal == nil
    }

    var rateText: String? {
        guard let group, currencyCode != group.currencyCode,
              let rate = activeRates?.rate(from: currencyCode, to: group.currencyCode) else { return nil }
        let value = rate.formatted(.number.locale(locale).precision(.significantDigits(2...6)))
        return String(localized: "1 \(currencyCode) = \(value) \(group.currencyCode)")
    }

    /// Finds the rate for the expense date in the background. Pinned group rate first, then the
    /// rate published for that day, then the latest. Saving never waits for it and an offline
    /// failure just leaves no converted value.
    func refreshRate() async {
        guard let group, currencyCode != group.currencyCode else {
            fetchedRates = nil
            isFindingRate = false
            return
        }
        let key = rateKey
        if fetchedRates?.key == key, fetchedRates?.rates != nil { return }
        isFindingRate = true
        let code = currencyCode
        let day = date
        let found: ExchangeRates?
        if let lookup = dependencies.rateLookup {
            found = await lookup(group, day, code)
        } else {
            found = await services.rates.exchangeRates(for: group, on: day, from: code)
        }
        guard !Task.isCancelled, key == rateKey else { return }
        fetchedRates = (key, found)
        isFindingRate = false
    }

    // MARK: Validation

    /// The first thing keeping Save off, or nil when the expense can be saved.
    var issue: ExpenseFormIssue? {
        guard let total, !total.isZero else { return .missingAmount }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingTitle }
        if case .issue(let issue) = payer.payers(total: total, locale: locale) { return issue }
        return splitIssue
    }

    var canSave: Bool { issue == nil && group != nil }

    var blockingReason: String? { issue?.message(locale: locale) }

    var payerIssue: ExpenseFormIssue? {
        guard let total, !total.isZero, case .issue(let issue) = payer.payers(total: total, locale: locale) else { return nil }
        return issue
    }

    var splitIssue: ExpenseFormIssue? {
        guard let total, !total.isZero else { return nil }
        switch splitResult(total: total) {
        case .success: return nil
        case .failure(let issue): return issue
        }
    }

    /// What the payers still owe against the total. Negative when over. Nil unless several people paid.
    var payerRemaining: Money? {
        guard let total else { return nil }
        return payer.remaining(total: total, locale: locale)
    }

    /// What is left to assign in the active split: money for exact and itemized, nil for other methods.
    var splitRemaining: Money? {
        guard let total, !total.isZero else { return nil }
        switch split.method {
        case .exact:
            let typed = participantList.compactMap { AmountInput.money(split.exact[$0.id, default: ""], currencyCode: currencyCode, locale: locale) }
            return Money(minorUnits: total.minorUnits - typed.reduce(0) { $0 + $1.minorUnits }, currencyCode: currencyCode)
        case .itemized:
            guard let items = split.itemizedTotal(currencyCode: currencyCode, locale: locale) else { return nil }
            return Money(minorUnits: total.minorUnits - items.minorUnits, currencyCode: currencyCode)
        default:
            return nil
        }
    }

    /// Percentage points left to assign, in hundredths. Nil unless splitting by percentage.
    var percentRemaining: Int64? {
        guard split.method == .percentage else { return nil }
        let typed = participantList.compactMap { AmountInput.basisPoints(split.percent[$0.id, default: ""], locale: locale) }
        return 10_000 - typed.reduce(0, +)
    }

    /// The people in the split with what each owes, for the live preview.
    var sharePreview: [(person: Person, amount: Money)] {
        guard let total, !total.isZero, case .success(let result) = splitResult(total: total) else { return [] }
        return members.compactMap { person in
            result.shares[person.id].map { (person, $0) }
        }
    }

    private func splitResult(total: Money) -> Result<ShareResult, ExpenseFormIssue> {
        let outcome = split.definition(participants: participants, currencyCode: total.currencyCode, locale: locale)
        guard case .definition(let definition) = outcome else {
            if case .issue(let issue) = outcome { return .failure(issue) }
            return .failure(.invalidSplit)
        }
        do {
            return .success(try SplitCalculator.calculate(definition, total: total))
        } catch let error as SplitError {
            return .failure(mapped(error))
        } catch {
            return .failure(.invalidSplit)
        }
    }

    private func mapped(_ error: SplitError) -> ExpenseFormIssue {
        switch error {
        case .noParticipants: .noParticipants
        case .exactAmountsDoNotMatchTotal(let expected, let actual):
            difference(expected: expected, actual: actual)
        case .itemizedTotalMismatch(let itemsAndCharges, let total):
            difference(expected: total, actual: itemsAndCharges)
        case .percentagesDoNotSumToHundred(let actual):
            actual < 10_000 ? .percentShort(basisPoints: 10_000 - actual) : .percentOver(basisPoints: actual - 10_000)
        case .negativePercentage, .negativeWeight, .negativeAmount: .negativeValue
        case .zeroTotalWeight: .noShares
        case .negativeShare(let id): .negativeShare(name: displayName(for: id))
        case .itemWithoutAssignees(let index):
            .itemWithoutPeople(name: split.items.indices.contains(index) ? itemName(split.items[index]) : "")
        default: .invalidSplit
        }
    }

    private func difference(expected: Money, actual: Money) -> ExpenseFormIssue {
        let gap = expected.minorUnits - actual.minorUnits
        let amount = Money(minorUnits: abs(gap), currencyCode: expected.currencyCode)
        return gap > 0 ? .splitShort(amount) : .splitOver(amount)
    }

    func itemName(_ item: ItemDraft) -> String {
        let trimmed = item.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "this item") : trimmed
    }

    /// A short line under the form: who pays what, or why Save is off.
    var statusText: String {
        if let reason = blockingReason { return reason }
        let preview = sharePreview
        guard let first = preview.first else { return "" }
        let amounts = Set(preview.map(\.amount))
        let people = preview.count
        if amounts.count == 1 {
            let each = MoneyFormatting.magnitudeString(first.amount, locale: locale)
            return String(localized: "Split between \(people) people, \(each) each.")
        }
        return String(localized: "Split between \(people) people.")
    }

    // MARK: Editing helpers

    func toggleParticipant(_ id: PersonID) {
        if participants.contains(id) {
            participants.remove(id)
        } else {
            participants.insert(id)
        }
    }

    func selectEveryone() {
        participants = Set(members.map(\.id))
    }

    func addItem() {
        split.items.append(ItemDraft(assignees: []))
    }

    func removeItems(at offsets: IndexSet) {
        split.items.remove(atOffsets: offsets)
    }

    func assign(_ person: PersonID, to item: ItemDraft.ID) {
        guard let index = split.items.firstIndex(where: { $0.id == item }) else { return }
        if split.items[index].assignees.contains(person) {
            split.items[index].assignees.remove(person)
        } else {
            split.items[index].assignees.insert(person)
        }
    }

    func assignEveryone(to item: ItemDraft.ID) {
        guard let index = split.items.firstIndex(where: { $0.id == item }) else { return }
        let everyone = Set(members.map(\.id))
        split.items[index].assignees = split.items[index].assignees == everyone ? [] : everyone
    }

    /// Sets the amount to what the items, tax and tip come to.
    func useItemsAsTotal() {
        guard let value = split.itemizedTotal(currencyCode: currencyCode, locale: locale), value.isPositive else { return }
        amountText = AmountInput.text(for: value, locale: locale)
    }

    func selectPayer(_ id: PersonID) {
        payer.single = id
    }

    func setMultiplePayers(_ enabled: Bool) {
        payer.isMultiple = enabled
        guard enabled else { return }
        if payer.selected.isEmpty, let single = payer.single ?? me?.id { payer.selected = [single] }
        if let total, payer.selected.count == 1, let only = payer.selected.first, payer.amounts[only, default: ""].isEmpty {
            payer.amounts[only] = AmountInput.text(for: total, locale: locale)
        }
    }

    func togglePayer(_ id: PersonID) {
        if payer.selected.contains(id) {
            payer.selected.remove(id)
        } else {
            payer.selected.insert(id)
        }
    }

    func splitPaymentsEvenly() {
        guard let total else { return }
        payer.splitEvenly(total: total, locale: locale)
    }

    func changeCurrency(to code: String) {
        currencyCode = code.uppercased()
    }

    func clearReceipt() {
        receipt = ReceiptAttachment()
    }

    /// The values that matter for "discard changes?".
    private struct Snapshot: Equatable {
        var amountText: String
        var currencyCode: String
        var title: String
        var category: ExpenseCategory
        var note: String
        var payer: PayerState
        var participants: Set<PersonID>
        var split: SplitEditorState
        var repeatChoice: RepeatChoice
        var receipt: ReceiptAttachment

        @MainActor init(_ model: ExpenseFormModel) {
            amountText = model.amountText
            currencyCode = model.currencyCode
            title = model.title
            category = model.category
            note = model.note
            payer = model.payer
            participants = model.participants
            split = model.split
            repeatChoice = model.repeatChoice
            receipt = model.receipt
        }
    }
}
