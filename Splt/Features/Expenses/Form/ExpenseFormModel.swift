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
    var isFindingRate = false
    /// The receipt item waiting for a tap on a person chip to be assigned.
    var selectedItemID: ItemDraft.ID?
    /// True while the payments were divided evenly by the payer chips, so they follow the amount.
    var payersFollowAmount = false
    @ObservationIgnored var fetchedRates: (key: String, rates: ExchangeRates?)?

    var describeText = ""
    var isReading = false
    var filledNotice: String?
    var unmatchedNames: [String] = []
    /// Names in a note that fit more than one person in the group.
    var ambiguousNames: [String] = []
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

    // MARK: Editing helpers

    func toggleParticipant(_ id: PersonID) {
        if participants.contains(id) {
            participants.remove(id)
        } else {
            participants.insert(id)
        }
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
