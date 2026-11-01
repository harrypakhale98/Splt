import Foundation
import SpltCore
import Synchronization
import Testing
@testable import Splt

/// A clock that moves forward one second every time it is read, so every reading is later than `start`
/// and than the one before.
final class TestClock: Sendable {
    let start: Date
    private let current: Mutex<Date>

    init(start: Date = Date(timeIntervalSince1970: 1_750_000_000)) {
        self.start = start
        self.current = Mutex(start)
    }

    func now() -> Date {
        current.withLock { value in
            value = value.addingTimeInterval(1)
            return value
        }
    }

    func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    var reading: @Sendable () -> Date {
        { [self] in now() }
    }
}

func usdAmount(_ cents: Int64) -> Money {
    Money(minorUnits: cents, currencyCode: "USD")
}
