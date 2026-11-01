extension Ledger {
    /// Currency codes that have any activity, sorted.
    public var currencies: [String] {
        netBalances.keys.sorted()
    }

    /// True when nobody owes anything in any currency.
    public var isSettled: Bool {
        netBalances.values.allSatisfy { table in table.values.allSatisfy(\.isZero) }
    }

    /// What one person is owed (positive) or owes (negative), one amount per currency, zeros left out.
    public func balances(of person: PersonID) -> [Money] {
        currencies.compactMap { currency in
            guard let amount = netBalances[currency]?[person], !amount.isZero else { return nil }
            return amount
        }
    }

    /// What each other person owes `me` (positive) or is owed by `me` (negative), per currency.
    /// Built from the direct debts between the two of you, so it ignores how the group as a
    /// whole could settle. People you are square with are left out.
    public func balances(with me: PersonID) -> [PersonID: [Money]] {
        var result: [PersonID: [Money]] = [:]
        for debt in debts {
            if debt.creditor == me {
                result[debt.debtor, default: []].append(debt.amount)
            } else if debt.debtor == me {
                let owed = Money(minorUnits: -debt.amount.minorUnits, currencyCode: debt.amount.currencyCode)
                result[debt.creditor, default: []].append(owed)
            }
        }
        return result
    }

    /// Net balances of everyone, converted into one currency.
    ///
    /// The converted balances still add up to zero: rounding is settled across people with the
    /// largest-remainder method rather than person by person.
    public func netBalances(in currencyCode: String, rates: ExchangeRates) throws -> [PersonID: Money] {
        var amounts: [PersonID: [Money]] = [:]
        for currency in currencies {
            for (person, amount) in netBalances[currency] ?? [:] {
                amounts[person, default: []].append(amount)
            }
        }
        return try rates.convert(amounts, to: currencyCode)
    }

    /// What each other person owes `me`, converted into one currency.
    public func balances(with me: PersonID, in currencyCode: String, rates: ExchangeRates) throws -> [PersonID: Money] {
        try rates.convert(balances(with: me), to: currencyCode)
    }
}
