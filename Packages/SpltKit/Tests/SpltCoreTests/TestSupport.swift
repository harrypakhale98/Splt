import Foundation
@testable import SpltCore

/// People with fixed ids so sorted order, and therefore tie-breaking, is predictable in tests.
func person(_ number: Int) -> PersonID {
    PersonID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!)
}

func usd(_ minorUnits: Int64) -> Money {
    Money(minorUnits: minorUnits, currencyCode: "USD")
}

func money(_ minorUnits: Int64, _ code: String) -> Money {
    Money(minorUnits: minorUnits, currencyCode: code)
}

func eur(_ minorUnits: Int64) -> Money {
    Money(minorUnits: minorUnits, currencyCode: "EUR")
}
