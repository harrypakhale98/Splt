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

    @Test func onlyTheClosingRowIsTheTotalBalance() throws {
        #expect(try parse("2025-03-14,Total balance,General,10.00,USD,5.00,-5.00").expenses.count == 1)
        let closing = try parse(",Total balance,,,USD,5.00,-5.00")
        #expect(closing.expenses.isEmpty)
        #expect(closing.warnings.isEmpty)
    }

    @Test func categoriesMatchWordsNotInsideThem() {
        #expect(SplitwiseCategoryMap.category(for: "Childcare") == .general)
        #expect(SplitwiseCategoryMap.category(for: "Gas/fuel") == .fuel)
        #expect(SplitwiseCategoryMap.category(for: "Bus/train") == .transport)
        #expect(SplitwiseCategoryMap.category(for: "Heat/gas") == .utilities)
        #expect(SplitwiseCategoryMap.category(for: "TV/Phone/Internet") == .utilities)
        #expect(SplitwiseCategoryMap.category(for: "Household supplies") == .home)
        #expect(SplitwiseCategoryMap.category(for: "Medical expenses") == .health)
    }

    @Test func readsUTF16WithAByteOrderMark() throws {
        var little = Data([0xFF, 0xFE])
        little.append(try #require("Date,Ana\n".data(using: .utf16LittleEndian)))
        #expect(SplitwiseFile.normalized(try SplitwiseFile.text(from: little)) == "Date,Ana")
        #expect(throws: SplitwiseFile.Unreadable.self) { try SplitwiseFile.text(from: Data([0x41, 0x00, 0x42])) }
    }

    @Test func aHugeFileIsRefusedBeforeItIsRead() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "huge-\(UUID().uuidString).csv")
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 20_000_001)
        try handle.close()
        #expect(throws: SplitwiseFile.Unreadable.self) { try SplitwiseFile.read(url) }
    }
}
