import Foundation
import PDFKit
import SpltCore
import Testing
@testable import Splt

@Suite("Group report and PDF")
struct GroupReportTests {
    private let english = GroupsTestCalendar.english
    private let me = Person(id: PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!), name: "Me", kind: .me)
    private let sam = Person(id: PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!), name: "Sam")
    private let priya = Person(id: PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!), name: "Priya")

    private var group: SplitGroup {
        SplitGroup(name: "Flat", currencyCode: "USD", memberIDs: [me.id, sam.id, priya.id])
    }

    private var people: [PersonID: Person] {
        [me.id: me, sam.id: sam, priya.id: priya]
    }

    private func expense(
        _ title: String, _ cents: Int64, day: Int, paidBy payer: Person, among members: [Person], deleted: Bool = false
    ) -> Expense {
        Expense(
            title: title, total: usdAmount(cents), date: utcDate(2026, 5, day), paidBy: payer.id,
            split: .equal(participants: Set(members.map(\.id))),
            deletedAt: deleted ? utcDate(2026, 5, 28) : nil
        )
    }

    private func report(simplifies: Bool = true) -> GroupReport {
        let expenses = [
            expense("Cab", 1500, day: 12, paidBy: sam, among: [sam, priya]),
            expense("Dinner", 3000, day: 10, paidBy: me, among: [me, sam, priya]),
            expense("Mistake", 9900, day: 11, paidBy: me, among: [me, sam], deleted: true)
        ]
        let payments = [Payment(payer: priya.id, receiver: me.id, amount: usdAmount(500), date: utcDate(2026, 5, 14))]
        let ledger = Ledger(expenses: expenses, payments: payments)
        return GroupReport(
            group: group, people: people, expenses: expenses, payments: payments,
            balances: GroupBalances(groupID: group.id, ledger: ledger, simplifiesDebts: simplifies),
            exportedAt: utcDate(2026, 5, 20)
        )
    }

    // MARK: Report

    @Test func expensesRunOldestFirstAndSkipDeletedOnes() {
        let report = report()
        #expect(report.expenses.map(\.title) == ["Dinner", "Cab"])
        #expect(report.expenses.first?.paidBy == "Me")
        #expect(report.totals == [usdAmount(4500)])
    }

    @Test func balancesFollowTheLedger() {
        let report = report()
        let byName = Dictionary(uniqueKeysWithValues: report.members.map { ($0.name, $0.amounts) })
        #expect(byName["Me"] == [usdAmount(1500)])
        #expect(byName["Sam"] == [usdAmount(-250)])
        #expect(byName["Priya"] == [usdAmount(-1250)])
    }

    @Test func simplifiedTransfersAreFewerThanDirectOnes() {
        let simplified = report(simplifies: true).transfers
        let direct = report(simplifies: false).transfers
        #expect(Set(simplified.map(\.to)) == ["Me"])
        #expect(simplified.map(\.amount.minorUnits).reduce(0, +) == 1500)
        #expect(simplified.count == 2)
        #expect(direct.count == 3)
    }

    @Test func paymentsAreListed() {
        let payments = report().payments
        #expect(payments.count == 1)
        #expect(payments.first?.from == "Priya")
        #expect(payments.first?.to == "Me")
        #expect(payments.first?.amount == usdAmount(500))
    }

    @Test func undoneAndUnknownPeopleAreHandled() {
        let ghost = PersonID()
        let expenses = [Expense(
            title: "Gift", total: usdAmount(1000), date: utcDate(2026, 5, 1), paidBy: ghost,
            split: .equal(participants: [ghost, me.id])
        )]
        let undone = Payment(payer: me.id, receiver: sam.id, amount: usdAmount(100), date: utcDate(2026, 5, 2), deletedAt: utcDate(2026, 5, 3))
        let report = GroupReport(
            group: group, people: people, expenses: expenses, payments: [undone],
            balances: GroupBalances(groupID: group.id, ledger: Ledger(expenses: expenses), simplifiesDebts: true),
            exportedAt: utcDate(2026, 5, 20)
        )
        #expect(report.expenses.first?.paidBy == "Someone")
        #expect(report.payments.isEmpty)
    }

    @Test func rowsReadTopToBottomWithAmountsOnTheRight() {
        let rows = report().rows(locale: english)
        #expect(rows.first == ReportRow(.title, "Flat"))
        #expect(rows.contains(ReportRow(.body, "Total spent", trailing: "$45.00")))
        #expect(rows.contains(ReportRow(.body, "Dinner", trailing: "$30.00")))
        #expect(rows.contains(ReportRow(.body, "Sam", trailing: "owes $2.50")))
        #expect(rows.contains(ReportRow(.body, "Me", trailing: "is owed $15.00")))
        #expect(rows.contains(ReportRow(.body, "Priya paid Me", trailing: "$5.00")))
        let headings = rows.filter { $0.style == .heading }.map(\.leading)
        #expect(headings == ["Balances", "To Settle Up", "By Person", "Expenses", "Payments"])
    }

    @Test func plainTextHasEveryRow() {
        let report = report()
        let lines = report.plainText(locale: english).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == report.rows(locale: english).count)
        #expect(lines.contains("Dinner  $30.00"))
        #expect(!lines.contains { $0.contains("Mistake") })
    }

    @Test func aSquareGroupSaysEveryoneIsSettled() {
        let balances = GroupBalances(groupID: group.id, ledger: Ledger(), simplifiesDebts: true)
        let empty = GroupReport(
            group: group, people: people, expenses: [], payments: [], balances: balances, exportedAt: utcDate(2026, 5, 20)
        )
        let text = empty.plainText(locale: english)
        #expect(text.contains("Everyone is settled up"))
        #expect(text.contains("No expenses"))
        #expect(text.contains("Me  Settled up"))
        #expect(!text.contains("Total spent"))
        #expect(!text.contains("Payments"))
    }

    // MARK: PDF

    private func document(_ report: GroupReport) throws -> PDFDocument {
        try #require(PDFDocument(data: GroupPDFRenderer.data(for: report, locale: english)))
    }

    @Test func thePDFHasAPageWithTheKnownContent() throws {
        let document = try document(report())
        #expect(document.pageCount == 1)
        let text = try #require(document.page(at: 0)?.string)
        #expect(!text.isEmpty)
        for expected in ["Flat", "Balances", "Dinner", "$30.00", "Cab", "$15.00", "Priya pays Me", "Payments"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
        #expect(!text.contains("Mistake"))
    }

    @Test func thePDFCarriesTheGroupNameAsItsTitle() throws {
        let attributes = try document(report()).documentAttributes
        #expect(attributes?[PDFDocumentAttribute.titleAttribute] as? String == "Flat")
    }

    @Test func aReportWithoutExpensesStillMakesAPage() throws {
        let balances = GroupBalances(groupID: group.id, ledger: Ledger(), simplifiesDebts: true)
        let empty = GroupReport(
            group: group, people: people, expenses: [], payments: [], balances: balances, exportedAt: utcDate(2026, 5, 20)
        )
        let document = try document(empty)
        #expect(document.pageCount == 1)
        #expect(document.string?.contains("No expenses") == true)
    }

    @Test func longReportsRunOntoMorePagesAndEveryPageHasText() throws {
        let many = (0..<150).map { index in
            expense("Item \(index)", 100, day: 1 + index % 28, paidBy: me, among: [me, sam])
        }
        let balances = GroupBalances(groupID: group.id, ledger: Ledger(expenses: many), simplifiesDebts: true)
        let long = GroupReport(
            group: group, people: people, expenses: many, payments: [], balances: balances, exportedAt: utcDate(2026, 5, 20)
        )
        let document = try document(long)
        #expect(document.pageCount > 2)
        for index in 0..<document.pageCount {
            #expect(document.page(at: index)?.string?.isEmpty == false, "page \(index) is empty")
        }
        let all = document.string ?? ""
        #expect(all.contains("Item 0"))
        #expect(all.contains("Item 149"))
    }

    @Test func aVeryLongNameDoesNotBreakTheLayout() throws {
        let name = String(repeating: "Long name ", count: 40)
        let balances = GroupBalances(groupID: group.id, ledger: Ledger(), simplifiesDebts: true)
        let odd = GroupReport(
            group: SplitGroup(name: name, currencyCode: "USD", memberIDs: [me.id]), people: people,
            expenses: [], payments: [], balances: balances, exportedAt: utcDate(2026, 5, 20)
        )
        let document = try document(odd)
        #expect(document.pageCount >= 1)
        #expect(document.string?.contains("Long name") == true)
    }
}
