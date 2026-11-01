import Foundation

/// An amount of money stored as whole minor units (cents) so arithmetic is exact.
public struct Money: Hashable, Sendable, Codable, Comparable {
    public var minorUnits: Int64
    public var currencyCode: String

    public init(minorUnits: Int64, currencyCode: String) {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.minorUnits < rhs.minorUnits
    }
}
