import Foundation

/// An amount of money stored as whole minor units (cents) so arithmetic is exact.
///
/// Currency codes are normalised to upper case. Ordering sorts by currency code first and
/// minor units second, which gives a stable total order; only compare amounts of the same
/// currency when the numeric order matters.
public struct Money: Hashable, Sendable, Codable, Comparable {
    public let minorUnits: Int64
    public let currencyCode: String

    public init(minorUnits: Int64, currencyCode: String) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode.uppercased()
    }

    /// Number of decimal places this currency uses.
    public var exponent: Int { Currency.minorUnitExponent(for: currencyCode) }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        if lhs.currencyCode != rhs.currencyCode { return lhs.currencyCode < rhs.currencyCode }
        return lhs.minorUnits < rhs.minorUnits
    }

    private enum CodingKeys: String, CodingKey {
        case minorUnits, currencyCode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            minorUnits: try container.decode(Int64.self, forKey: .minorUnits),
            currencyCode: try container.decode(String.self, forKey: .currencyCode)
        )
    }
}
