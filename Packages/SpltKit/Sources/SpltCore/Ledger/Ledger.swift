/// Balances for a set of expenses and payments.
///
/// The ledger never throws. Entries it cannot use (an invalid split, payers that do not add
/// up, a payment to yourself) are skipped and reported in `issues`, so one bad record cannot
/// hide everyone's balances. Deleted entries are ignored.
///
/// Amounts are kept per currency. Positive net balances mean a person is owed money,
/// negative means they owe.
public struct Ledger: Sendable {
    /// Net balance per person, keyed by currency code. Each currency's balances add up to zero.
    public let netBalances: [String: [PersonID: Money]]
    /// Direct debts between pairs of people, netted in both directions, never zero.
    /// Sorted by currency, then debtor, then creditor. After paying the shortcuts from
    /// `simplifiedDebts` everyone is settled but these direct debts can remain; they then
    /// cancel out when added up per person.
    public let debts: [Debt]
    /// Entries that were skipped, in the order they were found.
    public let issues: [LedgerIssue]

    public init(expenses: [Expense] = [], payments: [Payment] = []) {
        var accumulator = LedgerAccumulator()
        var issues: [LedgerIssue] = []

        for expense in expenses where !expense.isDeleted {
            do {
                let balances = try expense.netBalances()
                let net = balances.mapValues(\.minorUnits)
                let flows = try PairwiseFlows.flows(for: net)
                if !accumulator.apply(currency: expense.total.currencyCode, net: net, flows: flows) {
                    issues.append(.expense(expense.id, .overflow))
                }
            } catch let error as ExpenseError {
                issues.append(.expense(expense.id, error))
            } catch {
                issues.append(.expense(expense.id, .overflow))
            }
        }

        for payment in payments where !payment.isDeleted {
            do {
                try payment.validate()
            } catch let error as PaymentError {
                issues.append(.payment(payment.id, error))
                continue
            } catch {
                continue
            }
            let units = payment.amount.minorUnits
            let net = [payment.payer: units, payment.receiver: -units]
            let flow = DebtFlow(debtor: payment.receiver, creditor: payment.payer, amount: units)
            if !accumulator.apply(currency: payment.amount.currencyCode, net: net, flows: [flow]) {
                issues.append(.payment(payment.id, .overflow))
            }
        }

        self.netBalances = accumulator.net.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.mapValues { Money(minorUnits: $0, currencyCode: entry.key) }
        }
        self.debts = Ledger.debts(from: accumulator)
        self.issues = issues
    }

    private static func debts(from accumulator: LedgerAccumulator) -> [Debt] {
        var debts: [Debt] = []
        for (currency, table) in accumulator.pairs {
            for (pair, signed) in table where signed != 0 {
                let amount = Money(minorUnits: Int64(clamping: signed.magnitude), currencyCode: currency)
                debts.append(
                    signed > 0
                        ? Debt(debtor: pair.low, creditor: pair.high, amount: amount)
                        : Debt(debtor: pair.high, creditor: pair.low, amount: amount)
                )
            }
        }
        return debts.sorted { lhs, rhs in
            if lhs.amount.currencyCode != rhs.amount.currencyCode { return lhs.amount.currencyCode < rhs.amount.currencyCode }
            if lhs.debtor != rhs.debtor { return lhs.debtor < rhs.debtor }
            return lhs.creditor < rhs.creditor
        }
    }
}
