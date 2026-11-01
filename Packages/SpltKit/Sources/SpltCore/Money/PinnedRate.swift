import Foundation

/// A rate fixed by hand for one currency pair, for example the rate a group agreed on for a trip.
public struct PinnedRate: Hashable, Sendable, Codable {
    public let from: String
    public let to: String
    /// Units of `to` for one unit of `from`, in major units.
    public let rate: Decimal

    public init(from: String, to: String, rate: Decimal) {
        self.from = from.uppercased()
        self.to = to.uppercased()
        self.rate = rate
    }
}
