import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Group export and import")
struct GroupExportTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func populated() throws -> Fixture {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner, \"Luigi's\"", cents: 3000, date: Date(timeIntervalSince1970: 1_741_953_600))
        try fixture.addExpense("Taxi", cents: 1000, paidBy: fixture.sam, splitBetween: [fixture.sam.id, fixture.me.id], date: Date(timeIntervalSince1970: 1_742_040_000))
        let debt = Debt(debtor: fixture.priya.id, creditor: fixture.me.id, amount: usdAmount(500))
        try fixture.services.payments.settle(debt, in: fixture.group.id, date: Date(timeIntervalSince1970: 1_742_126_400))
        return fixture
    }

    @Test func csvSkipsAPaymentTheLedgerWouldSkip() throws {
        let fixture = try populated()
        let bad = Payment(payer: fixture.sam.id, receiver: fixture.me.id, amount: usdAmount(.min), date: fixture.clock.start)
        let snapshot = GroupExportSnapshot(
            group: fixture.group, people: [], expenses: [], payments: [bad], exportedAt: fixture.clock.start
        )
        #expect(!GroupCSVExporter.text(for: snapshot, timeZone: utc).contains(GroupCSVExporter.paymentCategory + ","))
    }

    @Test func csvStartsWithTheSplitwiseHeader() throws {
        let fixture = try populated()
        let text = String(decoding: try fixture.services.groups.export(group: fixture.group.id, format: .csv), as: UTF8.self)
        #expect(text.hasPrefix("Date,Description,Category,Cost,Currency,Me,Sam,Priya\n"))
    }

    @Test func csvHasOneRowPerEntryAndATotalBalanceRow() throws {
        let fixture = try populated()
        let snapshot = try snapshot(of: fixture)
        let rows = CSVText.rows(GroupCSVExporter.text(for: snapshot, timeZone: utc))
        #expect(rows.count == 1 + 3 + 1)
        #expect(rows[1][1] == "Dinner, \"Luigi's\"")
        #expect(rows[1][3] == "30.00")
        #expect(rows[1][5...] == ["20.00", "-10.00", "-10.00"])
        #expect(rows[3][2] == "Payment")
        #expect(rows[3][1] == "Priya paid Me")
        #expect(rows[4][1] == "Total balance")
    }

    @Test func csvTotalBalanceAddsUpToZero() throws {
        let fixture = try populated()
        let rows = CSVText.rows(GroupCSVExporter.text(for: try snapshot(of: fixture), timeZone: utc))
        let total = try #require(rows.last)
        let cents = try total[5...].map {
            try MoneyParser.parse($0, currencyCode: "USD", locale: GroupCSVExporter.posix).minorUnits
        }
        #expect(cents.count == 3)
        #expect(cents.reduce(0, +) == 0)
    }

    @Test func csvOmitsDeletedEntries() throws {
        let fixture = try populated()
        let extra = try fixture.addExpense("Mistake", cents: 999)
        try fixture.services.expenses.delete(id: extra.id)
        let text = String(decoding: try fixture.services.groups.export(group: fixture.group.id, format: .csv), as: UTF8.self)
        #expect(!text.contains("Mistake"))
    }

    @Test func csvNeutralizesFormulasInTitlesAndNames() throws {
        let fixture = try Fixture()
        try fixture.addExpense("=HYPERLINK(\"http://example.com\")", cents: 100)
        let text = String(decoding: try fixture.services.groups.export(group: fixture.group.id, format: .csv), as: UTF8.self)
        #expect(CSVText.rows(text)[1][1].hasPrefix("'="))
    }

    @Test func csvNeutralizesACurrencyFromAnotherDevice() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Dinner")
        let context = fixture.services.environment.context
        try #require(try ExpenseRecord.find(recordName: expense.id.description, in: context)).currencyCode = "=1+"
        try context.save()
        let text = String(decoding: try fixture.services.groups.export(group: fixture.group.id, format: .csv), as: UTF8.self)
        let rows = CSVText.rows(text)
        #expect(!rows.contains { row in row.contains { $0.hasPrefix("=") } })
    }

    @Test func exportedCSVImportsBackToTheSameBalances() throws {
        let source = try populated()
        let csv = String(decoding: try source.services.groups.export(group: source.group.id, format: .csv), as: UTF8.self)
        let sourceBalances = try source.services.groups.balances(for: source.group.id)

        let target = try Fixture()
        let summary = try target.services.groups.importSplitwiseCSV(csv, into: target.group.id)
        #expect(summary.expensesAdded == 2)
        #expect(summary.paymentsAdded == 1)
        #expect(summary.peopleAdded == 0)
        #expect(summary.warnings.isEmpty)
        let imported = try target.services.groups.balances(for: target.group.id)

        let sourceByName = [("Me", source.me.id), ("Sam", source.sam.id), ("Priya", source.priya.id)]
        let targetByName = [("Me", target.me.id), ("Sam", target.sam.id), ("Priya", target.priya.id)]
        for (index, entry) in sourceByName.enumerated() {
            #expect(sourceBalances.net(for: entry.1) == imported.net(for: targetByName[index].1))
        }
    }

    @Test func importCreatesPlaceholdersForNewNamesAndAddsThemToTheGroup() throws {
        let fixture = try Fixture()
        let csv = """
        Date,Description,Category,Cost,Currency,Me,Zed
        2025-03-14,Lunch,Dining out,20.00,USD,10.00,-10.00
        """
        let summary = try fixture.services.groups.importSplitwiseCSV(csv, into: fixture.group.id)
        #expect(summary.peopleAdded == 1)
        let zed = try #require(try fixture.services.people.allPeople().first { $0.name == "Zed" })
        #expect(zed.kind == .placeholder)
        let group = try #require(try fixture.services.groups.group(id: fixture.group.id))
        #expect(group.memberIDs.contains(zed.id))
        let kinds = try fixture.services.activity.entries(in: fixture.group.id, limit: 10).map(\.event.kind)
        #expect(kinds.filter { $0 == .expensesImported }.count == 1)
        #expect(!kinds.contains(.expenseAdded))
    }

    @Test func importOfABadFileChangesNothing() throws {
        let fixture = try Fixture()
        #expect(throws: DataError.self) {
            try fixture.services.groups.importSplitwiseCSV("nonsense", into: fixture.group.id)
        }
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).isEmpty)
    }

    @Test func jsonExportDecodesBackToTheSameExpensesAndPayments() throws {
        let fixture = try populated()
        let data = try fixture.services.groups.export(group: fixture.group.id, format: .json)
        let document = try GroupJSONExporter.decode(data)
        #expect(document.formatVersion == 1)
        #expect(document.group.id == fixture.group.id)
        #expect(document.people.map(\.name) == ["Me", "Sam", "Priya"])
        #expect(Set(document.expenses.map(\.id)) == Set(try fixture.services.expenses.expenses(in: fixture.group.id).map(\.id)))
        #expect(document.payments == (try fixture.services.payments.payments(in: fixture.group.id)))
        #expect(!String(decoding: data, as: UTF8.self).contains("contactHint"))
    }

    @Test func exportOfAnUnknownGroupThrows() throws {
        let fixture = try Fixture()
        #expect(throws: DataError.self) { try fixture.services.groups.export(group: GroupID(), format: .csv) }
    }

    @Test func exportListsFormerMembersWhoAppearInOldExpenses() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        let payment = Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usdAmount(1500))
        try fixture.services.payments.settle(payment, in: fixture.group.id, date: fixture.clock.start)
        try fixture.services.groups.removeMember(fixture.sam.id, from: fixture.group.id)
        let text = String(decoding: try fixture.services.groups.export(group: fixture.group.id, format: .csv), as: UTF8.self)
        #expect(text.hasPrefix("Date,Description,Category,Cost,Currency,Me,Priya,Sam\n"))
    }

    private func snapshot(of fixture: Fixture) throws -> GroupExportSnapshot {
        GroupExportSnapshot(
            group: fixture.group, people: [fixture.me, fixture.sam, fixture.priya],
            expenses: try fixture.services.expenses.expenses(in: fixture.group.id).sorted { $0.date < $1.date },
            payments: try fixture.services.payments.payments(in: fixture.group.id), exportedAt: fixture.clock.start
        )
    }
}
