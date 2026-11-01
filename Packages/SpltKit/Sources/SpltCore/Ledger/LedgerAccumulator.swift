struct PersonPair: Hashable, Sendable {
    let low: PersonID
    let high: PersonID

    init(_ first: PersonID, _ second: PersonID) {
        low = min(first, second)
        high = max(first, second)
    }
}

/// Running totals for a ledger, kept per currency in plain integers.
struct LedgerAccumulator: Sendable {
    private(set) var net: [String: [PersonID: Int64]] = [:]
    /// Per currency and person pair: what the lower id owes the higher id. Negative means the reverse.
    private(set) var pairs: [String: [PersonPair: Int64]] = [:]

    /// Adds one entry. Returns false, leaving the totals untouched, if any sum would overflow.
    mutating func apply(currency: String, net entryNet: [PersonID: Int64], flows: [DebtFlow]) -> Bool {
        var netTotals = net[currency] ?? [:]
        var pairTotals = pairs[currency] ?? [:]

        for (person, amount) in entryNet {
            let (sum, overflow) = (netTotals[person] ?? 0).addingReportingOverflow(amount)
            if overflow { return false }
            netTotals[person] = sum
        }
        for flow in flows {
            let pair = PersonPair(flow.debtor, flow.creditor)
            let signed = flow.debtor == pair.low ? flow.amount : -flow.amount
            let (sum, overflow) = (pairTotals[pair] ?? 0).addingReportingOverflow(signed)
            if overflow { return false }
            pairTotals[pair] = sum
        }

        net[currency] = netTotals
        pairs[currency] = pairTotals
        return true
    }
}
