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

extension DataServices {
    /// Stores expenses the way the importer does: checked as one batch and saved once, or not at all.
    func insertBatch(_ expenses: [Expense]) throws {
        do {
            try SwiftDataExpenseRepository(environment).insertBatch(expenses, createdBy: try people.me()?.id)
            try environment.save()
        } catch {
            environment.tracker.rollback()
            throw error
        }
    }

    /// Removes a person the way sync or a merge does. Nothing in the app deletes a person directly.
    func removePerson(_ id: PersonID) throws {
        guard let record = try environment.personRecord(id) else { return }
        environment.tracker.tombstone(record)
        try environment.save()
    }
}

func usdAmount(_ cents: Int64) -> Money {
    Money(minorUnits: cents, currencyCode: "USD")
}
