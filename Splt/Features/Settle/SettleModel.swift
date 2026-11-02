import Foundation
import Observation
import SwiftUI
import SpltCore

/// The state behind the settle up sheet: what is being paid, by whom, and the payments it will write.
@MainActor
@Observable
final class SettleModel {
    enum AmountMode: Hashable, Sendable {
        case full
        case partial
    }

    enum AmountIssue: Equatable, Sendable {
        case empty
        case invalid
        case notPositive
        case exceedsBalance(Money)
    }

    let route: SettleRoute
    var amountMode: AmountMode = .full {
        didSet { if amountMode == .partial, amountText.isEmpty { amountText = fullAmount?.plainString(locale: locale) ?? "" } }
    }
    var amountText = ""
    /// Flips who paid whom when there is a single debt.
    var isReversed = false
    var date: Date
    var note = ""
    var method: SettleMethod {
        didSet { defaults.set(method.rawValue, forKey: Self.methodKey) }
    }
    private(set) var receipt: SettleReceipt?
    var errorMessage: String?

    private(set) var me: Person?
    private(set) var peopleByID: [PersonID: Person] = [:]

    static let methodKey = "settle.lastMethod"

    @ObservationIgnored private let payments: any PaymentRepository
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locale: Locale

    init(
        route: SettleRoute,
        services: DataServices,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        locale: Locale = .current
    ) {
        self.route = route
        self.payments = services.payments
        self.defaults = defaults
        self.locale = locale
        self.date = now
        self.method = defaults.string(forKey: Self.methodKey).flatMap(SettleMethod.init(rawValue:)) ?? .cash
        me = try? services.people.me()
        peopleByID = Dictionary(
            ((try? services.people.allPeople()) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: What is being paid

    var isBatch: Bool { route.debts.count > 1 }

    /// The debt being edited when there is exactly one.
    var singleDebt: Debt? { route.debts.count == 1 ? route.debts.first : nil }

    var fullAmount: Money? { singleDebt?.amount }

    var payer: PersonID? {
        guard let debt = singleDebt else { return nil }
        return isReversed ? debt.creditor : debt.debtor
    }

    var receiver: PersonID? {
        guard let debt = singleDebt else { return nil }
        return isReversed ? debt.debtor : debt.creditor
    }

    /// The amount that will be recorded for a single debt, nil while the text is not a valid amount.
    var amount: Money? {
        guard let debt = singleDebt else { return nil }
        switch amountMode {
        case .full:
            return debt.amount
        case .partial:
            guard let parsed = try? MoneyParser.parse(
                amountText, currencyCode: debt.amount.currencyCode, locale: locale, allowNegative: false
            ), parsed.isPositive else { return nil }
            return parsed
        }
    }

    var amountIssue: AmountIssue? {
        guard let debt = singleDebt, amountMode == .partial else { return nil }
        if amountText.trimmingCharacters(in: .whitespaces).isEmpty { return .empty }
        guard let parsed = try? MoneyParser.parse(
            amountText, currencyCode: debt.amount.currencyCode, locale: locale, allowNegative: false
        ) else { return .invalid }
        if !parsed.isPositive { return .notPositive }
        if !isReversed, parsed.minorUnits > debt.amount.minorUnits { return .exceedsBalance(debt.amount) }
        return nil
    }

    /// What is left of the debt after a partial payment.
    var remaining: Money? {
        guard let amount, let full = fullAmount, !isReversed, amount.minorUnits < full.minorUnits else { return nil }
        return Money(minorUnits: full.minorUnits - amount.minorUnits, currencyCode: full.currencyCode)
    }

    // MARK: Share of the debt

    /// The step of the stepper and the drag: a whole unit of the currency, or a tenth of one for small debts.
    var step: Int64 {
        guard let full = fullAmount else { return 1 }
        let one = Int64(pow(10, Double(full.exponent)))
        return full.minorUnits >= 10 * one ? one : max(one / 10, 1)
    }

    /// How much of the debt is being paid, from 0 to 1. A payment above the debt counts as all of it.
    var fraction: Double {
        guard let amount, let full = fullAmount, full.minorUnits > 0 else { return 1 }
        return min(Double(amount.minorUnits) / Double(full.minorUnits), 1)
    }

    /// Pays this share of the debt, rounded to the step. Everything above 98 percent means all of it.
    func setFraction(_ value: Double) {
        guard let full = fullAmount, !isReversed else { return }
        let clamped = min(max(value, 0), 1)
        if clamped >= 0.98 {
            amountMode = .full
            return
        }
        let raw = Int64((Double(full.minorUnits) * clamped).rounded())
        let units = max((raw / step) * step, step)
        setPartial(units)
    }

    /// Moves the amount by whole steps, for the stepper and for VoiceOver. Never below one step.
    func nudge(by steps: Int) {
        guard let full = fullAmount, let current = amount else { return }
        var units = current.minorUnits + Int64(steps) * step
        units = max(units, step)
        if !isReversed, units >= full.minorUnits {
            amountMode = .full
            return
        }
        setPartial(units)
    }

    private func setPartial(_ units: Int64) {
        guard let full = fullAmount else { return }
        amountMode = .partial
        amountText = Money(minorUnits: units, currencyCode: full.currencyCode).plainString(locale: locale)
    }

    var totals: [Money] {
        if let amount { return [amount] }
        return MoneyTotals.sum(route.debts.map(\.amount))
    }

    var canRecord: Bool {
        receipt == nil && !route.debts.isEmpty && (isBatch || (amount != nil && amountIssue == nil))
    }

    // MARK: Names

    func name(of id: PersonID) -> String {
        if id == me?.id { return String(localized: "You") }
        return peopleByID[id]?.name ?? String(localized: "Someone")
    }

    /// "You pay Sam", "Sam pays you" or "Sam pays Priya".
    func sentence(payer: PersonID, receiver: PersonID) -> String {
        let to = name(of: receiver)
        let from = name(of: payer)
        if payer == me?.id { return String(localized: "You pay \(to)") }
        if receiver == me?.id { return String(localized: "\(from) pays you") }
        return String(localized: "\(from) pays \(to)")
    }

    /// The people of the payment with the colors they carry, payer first. A whole group lists everyone involved.
    var participants: [SettleParticipant] {
        var ordered: [PersonID] = []
        if let payer, let receiver {
            ordered = [payer, receiver]
        } else {
            for debt in route.debts {
                for id in [debt.debtor, debt.creditor] where !ordered.contains(id) { ordered.append(id) }
            }
        }
        return ordered.map {
            SettleParticipant(
                id: $0, name: name(of: $0), color: PersonPalette.color(for: $0), avatarName: peopleByID[$0]?.name
            )
        }
    }

    var headline: String {
        if let payer, let receiver { return sentence(payer: payer, receiver: receiver) }
        return String(localized: "Settle everything")
    }

    // MARK: Pay with

    /// The address that the "Pay with" button opens. Only when you are the one paying.
    var payWithURL: URL? {
        guard method.supportsPayWith, let amount, let payer, payer == me?.id, let receiver else { return nil }
        return method.paymentURL(
            amount: amount, note: note, recipient: peopleByID[receiver]?.contactHint
        )
    }

    // MARK: Recording

    func makePayments() -> [Payment] {
        let text = SettleNote.compose(method: method, text: note)
        if singleDebt != nil, let amount, let payer, let receiver {
            return [Payment(groupID: route.groupID, payer: payer, receiver: receiver, amount: amount, date: date, note: text)]
        }
        return route.debts.map {
            Payment(groupID: route.groupID, payer: $0.debtor, receiver: $0.creditor, amount: $0.amount, date: date, note: text)
        }
    }

    /// Writes the payments. Returns the receipt, or nil after setting `errorMessage`.
    @discardableResult
    func record() -> SettleReceipt? {
        guard canRecord else { return nil }
        let planned = makePayments()
        var saved: [Payment] = []
        do {
            for payment in planned {
                try payments.record(payment)
                saved.append(payment)
            }
        } catch {
            for payment in saved { try? payments.undo(id: payment.id) }
            errorMessage = SettleErrorMessage.text(for: error)
            return nil
        }
        let made = SettleReceipt(
            paymentIDs: saved.map(\.id), message: message(for: saved), total: MoneyTotals.sum(saved.map(\.amount))
        )
        receipt = made
        errorMessage = nil
        return made
    }

    func undo() {
        guard let receipt else { return }
        for id in receipt.paymentIDs { try? payments.undo(id: id) }
        self.receipt = nil
    }

    private func message(for saved: [Payment]) -> String {
        if saved.count == 1, let payment = saved.first {
            let amount = MoneyFormatting.magnitudeString(payment.amount, locale: locale)
            let to = name(of: payment.receiver), from = name(of: payment.payer)
            if payment.payer == me?.id { return String(localized: "You paid \(to) \(amount)") }
            if payment.receiver == me?.id { return String(localized: "\(from) paid you \(amount)") }
            return String(localized: "\(from) paid \(to) \(amount)")
        }
        return String(localized: "Recorded \(saved.count) payments")
    }
}

enum SettleErrorMessage {
    static func text(for error: any Error) -> String {
        if let error = error as? DataError {
            switch error {
            case .invalidPayment: return String(localized: "That payment isn't valid. Check the amount and who is paying.")
            case .notFound, .missingGroup: return String(localized: "That group is no longer available.")
            default: break
            }
        }
        return String(localized: "Something went wrong. Please try again.")
    }
}
