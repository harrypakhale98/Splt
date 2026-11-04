import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Splitwise import edge cases")
struct SplitwiseImportEdgeCaseTests {
    private func parse(_ row: String) throws -> SplitwiseImport {
        try SplitwiseCSVImporter.parse(
            "Date,Description,Category,Cost,Currency,Ana,Ben\n\(row)\n", groupID: GroupID(), timeZone: TimeZone(identifier: "UTC")!
        )
    }

    @Test func absurdAmountsAreSkippedNotFatal() throws {
        let members = try parse("2025-03-14,X,General,1.00,USD,90000000000000000,90000000000000000")
        #expect(members.expenses.isEmpty)
        #expect(members.warnings.count == 1)
        let cost = try parse("2025-03-14,X,General,90000000000000000,USD,1.00,-1.00")
        #expect(cost.expenses.isEmpty)
        #expect(cost.warnings.count == 1)
    }

    @Test func aShortYearIsNotADate() throws {
        let result = try parse("25-03-14,X,General,10.00,USD,5.00,-5.00")
        #expect(result.expenses.isEmpty)
        #expect(result.warnings.map(\.message) == ["Unreadable date."])
    }

    @Test func aPaymentMustMatchItsMembers() throws {
        let wrong = try parse("2025-03-14,X,Payment,99.00,USD,5.00,-5.00")
        #expect(wrong.payments.isEmpty)
        #expect(wrong.warnings.count == 1)
        #expect(try parse("2025-03-14,X,Payment,5.00,USD,5.00,-5.00").payments.count == 1)
    }

    @Test func aCurrencyMustBeLetters() throws {
        let result = try parse("2025-03-14,X,General,10.00,=1+,5.00,-5.00")
        #expect(result.expenses.isEmpty)
        #expect(result.warnings.map(\.message) == ["Missing currency."])
    }
}
