import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Splitwise CSV importer")
struct SplitwiseCSVImporterTests {
    private let group = GroupID()
    private let utc = TimeZone(identifier: "UTC")!

    private func parse(_ rows: [String], known: [String: PersonID] = [:]) throws -> SplitwiseImport {
        let text = (["Date,Description,Category,Cost,Currency,Ana,Ben,Cy"] + rows).joined(separator: "\n")
        return try SplitwiseCSVImporter.parse(text, groupID: group, knownPeople: known, timeZone: utc)
    }

    @Test func readsTheMemberColumns() throws {
        let result = try parse([])
        #expect(result.memberNames == ["Ana", "Ben", "Cy"])
        #expect(Set(result.members.keys) == ["Ana", "Ben", "Cy"])
        #expect(Set(result.members.values).count == 3)
    }

    @Test func reusesKnownPeopleByNameIgnoringCase() throws {
        let ana = PersonID()
        let result = try parse([], known: ["ana": ana])
        #expect(result.members["Ana"] == ana)
    }

    @Test func rebuildsAnEqualSplitPaidByOnePerson() throws {
        let result = try parse(["2025-03-14,Dinner,Dining out,30.00,USD,20.00,-10.00,-10.00"])
        let expense = try #require(result.expenses.first)
        let ana = try #require(result.members["Ana"])
        #expect(expense.title == "Dinner")
        #expect(expense.category == .dining)
        #expect(expense.total == usdAmount(3000))
        #expect(expense.payers == [ana: usdAmount(3000)])
        #expect(expense.split == .equal(participants: Set(result.members.values)))
        #expect(expense.groupID == group)
        #expect(result.warnings.isEmpty)
    }

    @Test func aPayerWhoOwesNothingIsLeftOutOfTheSplit() throws {
        let result = try parse(["2025-03-14,Gift for Cy,Gifts,40.00,USD,40.00,-20.00,-20.00"])
        let expense = try #require(result.expenses.first)
        let ana = try #require(result.members["Ana"])
        #expect(expense.split == .equal(participants: Set(result.members.values).subtracting([ana])))
    }

    @Test func rebuildsUnequalSharesAsExactAmounts() throws {
        let result = try parse(["2025-03-14,Groceries,Groceries,30.00,USD,22.00,-8.00,-14.00"])
        let expense = try #require(result.expenses.first)
        let members = result.members
        #expect(expense.split == .exact(amounts: [
            members["Ana"]!: usdAmount(800), members["Ben"]!: usdAmount(800), members["Cy"]!: usdAmount(1400)
        ]))
        #expect(try expense.netBalances()[members["Ana"]!] == usdAmount(2200))
    }

    @Test func roundingCentsStayWithinTheEqualSplit() throws {
        let result = try parse(["2025-03-14,Taxi,Taxi,10.00,USD,6.66,-3.33,-3.33"])
        let expense = try #require(result.expenses.first)
        try expense.validate()
        #expect(expense.total == usdAmount(1000))
        #expect(try expense.netBalances().values.map(\.minorUnits).reduce(0, +) == 0)
    }

    @Test func rebuildsRefundsWithNegativeAmounts() throws {
        let result = try parse(["2025-03-14,Refund,General,-30.00,USD,-20.00,10.00,10.00"])
        let expense = try #require(result.expenses.first)
        try expense.validate()
        #expect(expense.total == usdAmount(-3000))
        #expect(expense.isRefund)
        let balances = try expense.netBalances()
        #expect(balances[result.members["Ana"]!] == usdAmount(-2000))
    }

    @Test func severalPayersAreRebuiltAsAnEqualSplit() throws {
        let result = try parse(["2025-03-14,Bar,Dining out,60.00,USD,10.00,10.00,-20.00"])
        let expense = try #require(result.expenses.first)
        try expense.validate()
        #expect(expense.payers.values.map(\.minorUnits).reduce(0, +) == 6000)
        let balances = try expense.netBalances()
        #expect(balances[result.members["Cy"]!] == usdAmount(-2000))
    }

    @Test func severalPayersWithUnequalSharesKeepEveryBalance() throws {
        let result = try parse([
            "2025-03-14,Hotel,General,100.00,USD,50.00,30.00,-80.00",
            "2025-03-15,Hotel refund,General,-100.00,USD,-50.00,-30.00,80.00"
        ])
        #expect(result.warnings.isEmpty)
        #expect(result.expenses.count == 2)
        let members = result.members
        let cells: [String: Int64] = ["Ana": 5000, "Ben": 3000, "Cy": -8000]

        let hotel = try #require(result.expenses.first)
        try hotel.validate()
        #expect(hotel.total == usdAmount(10000))
        #expect(hotel.payers.values.map(\.minorUnits).reduce(0, +) == 10000)
        let balances = try hotel.netBalances()
        for (name, cents) in cells {
            #expect(balances[members[name]!] == usdAmount(cents))
        }

        let refund = try #require(result.expenses.last)
        try refund.validate()
        #expect(refund.total == usdAmount(-10000))
        let refunded = try refund.netBalances()
        for (name, cents) in cells {
            #expect(refunded[members[name]!] == usdAmount(-cents))
        }
    }

    @Test func settlementsBecomePayments() throws {
        let result = try parse(["2025-03-20,Ben paid Ana,Payment,15.00,USD,-15.00,15.00,"])
        let payment = try #require(result.payments.first)
        #expect(payment.payer == result.members["Ben"])
        #expect(payment.receiver == result.members["Ana"])
        #expect(payment.amount == usdAmount(1500))
        #expect(result.expenses.isEmpty)
    }

    @Test func skipsTheTotalBalanceRowAndBlankLines() throws {
        let result = try parse(["", "2025-03-14,Dinner,Dining out,30.00,USD,20.00,-10.00,-10.00", ",Total balance,,,USD,20.00,-10.00,-10.00"])
        #expect(result.expenses.count == 1)
        #expect(result.warnings.isEmpty)
    }

    @Test func parsesDatesAtNoonInTheGivenZone() throws {
        let result = try parse(["2025-03-14,Dinner,General,30.00,USD,20.00,-10.00,-10.00"])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: try #require(result.expenses.first).date)
        #expect(parts.year == 2025 && parts.month == 3 && parts.day == 14 && parts.hour == 12)
    }

    @Test func handlesOtherCurrenciesAndQuotedDescriptions() throws {
        let result = try parse(["2025-03-14,\"Sushi, take away\",Dining out,6000,JPY,4000,-2000,-2000"])
        let expense = try #require(result.expenses.first)
        #expect(expense.title == "Sushi, take away")
        #expect(expense.total == Money(minorUnits: 6000, currencyCode: "JPY"))
    }

    @Test func badRowsBecomeWarningsAndTheRestStillImport() throws {
        let result = try parse([
            "not a date,Dinner,General,30.00,USD,20.00,-10.00,-10.00",
            "2025-03-14,Odd,General,30.00,USD,20.00,-10.00,-5.00",
            "2025-03-14,Free,General,0.00,USD,0,0,0",
            "2025-03-14,Letters,General,abc,USD,0,0,0",
            "2025-03-14,Good,General,30.00,USD,20.00,-10.00,-10.00"
        ])
        #expect(result.expenses.map(\.title) == ["Good"])
        #expect(result.warnings.map(\.line) == [2, 3, 4, 5])
    }

    @Test func aPaymentNeedsExactlyTwoPeople() throws {
        let result = try parse(["2025-03-20,Mixed,Payment,15.00,USD,10.00,-5.00,-5.00"])
        #expect(result.payments.isEmpty)
        #expect(result.warnings.count == 1)
    }

    @Test func missingHeaderColumnsAreAnError() {
        #expect(throws: DataError.self) {
            try SplitwiseCSVImporter.parse("Date,Description,Cost\n", groupID: group, timeZone: utc)
        }
        #expect(throws: DataError.self) {
            try SplitwiseCSVImporter.parse("", groupID: group, timeZone: utc)
        }
    }

    @Test func aHeaderInAnotherLanguageIsReadByPosition() throws {
        let text = [
            "Fecha,Descripción,Categoría,Coste,Moneda,Ana,Ben,Cy",
            "2025-03-14,Cena,Restaurantes,30.00,USD,20.00,-10.00,-10.00",
            "",
            ",Saldo total,,,USD,20.00,-10.00,-10.00"
        ].joined(separator: "\n")
        let result = try SplitwiseCSVImporter.parse(text, groupID: group, timeZone: utc)
        #expect(result.memberNames == ["Ana", "Ben", "Cy"])
        #expect(result.warnings.isEmpty)
        let expense = try #require(result.expenses.first)
        #expect(result.expenses.count == 1)
        #expect(expense.title == "Cena")
        #expect(expense.total == usdAmount(3000))
        #expect(expense.payers == [try #require(result.members["Ana"]): usdAmount(3000)])
    }

    @Test func otherTablesAreStillRefused() {
        // enough columns, but nothing in the first one is a date
        #expect(throws: DataError.unreadableCSV("The header has no date column.")) {
            try SplitwiseCSVImporter.parse("a,b,c,d,e,f,g\n1,2,3,4,5,6,7\n", groupID: group, timeZone: utc)
        }
        #expect(throws: DataError.self) {
            try SplitwiseCSVImporter.parse("Fecha,Descripción,Categoría,Coste,Moneda,Ana\n", groupID: group, timeZone: utc)
        }
        // too few columns to hold a member
        #expect(throws: DataError.self) {
            try SplitwiseCSVImporter.parse("Fecha,Descripción,Categoría,Coste,Moneda\n2025-03-14,Cena,x,30.00,USD\n", groupID: group, timeZone: utc)
        }
    }

    @Test func mapsSplitwiseCategoryNames() {
        #expect(SplitwiseCategoryMap.category(for: "Dining out") == .dining)
        #expect(SplitwiseCategoryMap.category(for: "Groceries") == .groceries)
        #expect(SplitwiseCategoryMap.category(for: "Gas/fuel") == .fuel)
        #expect(SplitwiseCategoryMap.category(for: "Taxi") == .transport)
        #expect(SplitwiseCategoryMap.category(for: "Rent") == .rent)
        #expect(SplitwiseCategoryMap.category(for: "Electricity") == .utilities)
        #expect(SplitwiseCategoryMap.category(for: "Something else") == .general)
        #expect(SplitwiseCategoryMap.category(for: "health") == .health)
    }
}
