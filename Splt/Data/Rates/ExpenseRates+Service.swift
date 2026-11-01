extension ExpenseRates {
    /// Rates from the service's snapshot: the group's pinned rate first, then the latest cached table.
    /// The form asks without waiting, so this never touches the network; the service fills the snapshot.
    static func cached(by service: RatesService) -> ExpenseRates {
        ExpenseRates { service.snapshot.exchangeRates(for: $0) }
    }
}
