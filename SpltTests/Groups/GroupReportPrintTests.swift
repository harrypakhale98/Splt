import Foundation
import PDFKit
import SpltCore
import Testing
@testable import Splt

@Suite("Group report on paper")
struct GroupReportPrintTests {
    private let english = GroupsTestCalendar.english
    private let me = Person(id: PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!), name: "Me", kind: .me)
    private let sam = Person(id: PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!), name: "Sam")
    private let priya = Person(id: PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!), name: "Priya")

    private var people: [PersonID: Person] { [me.id: me, sam.id: sam, priya.id: priya] }

    private func expense(_ title: String, _ cents: Int64, day: Int, paidBy payer: Person, among members: [Person]) -> Expense {
        Expense(
            title: title, total: usdAmount(cents), date: utcDate(2026, 5, day), paidBy: payer.id,
            split: .equal(participants: Set(members.map(\.id)))
        )
    }

    private func report(
        members: [Person], expenses: [Expense], payments: [Payment] = [], name: String = "Lisbon Trip"
    ) -> GroupReport {
        let group = SplitGroup(name: name, currencyCode: "USD", memberIDs: members.map(\.id))
        return GroupReport(
            group: group, people: people, expenses: expenses, payments: payments,
            balances: GroupBalances(groupID: group.id, ledger: Ledger(expenses: expenses, payments: payments), simplifiesDebts: true),
            exportedAt: utcDate(2026, 5, 20)
        )
    }

    private var refundReport: GroupReport {
        report(
            members: [me, sam, priya],
            expenses: [
                expense("Museum tickets", 9000, day: 10, paidBy: sam, among: [me, sam, priya]),
                expense("Museum tickets refund", -2400, day: 11, paidBy: sam, among: [me, sam, priya])
            ],
            payments: [Payment(payer: priya.id, receiver: sam.id, amount: usdAmount(1000), date: utcDate(2026, 5, 12))]
        )
    }

    // MARK: Signs

    @Test func aRefundPrintsWithAMinusSignAndSaysWhoGotTheMoney() {
        let rows = refundReport.rows(locale: english)
        let refund = rows.firstIndex(of: ReportRow(.body, "Museum tickets refund", trailing: "\u{2212}$24.00"))
        #expect(refund != nil)
        if let refund {
            #expect(rows[refund + 1].leading.contains("refund received by Sam"))
        }
        #expect(rows.contains(ReportRow(.body, "Museum tickets", trailing: "$90.00")))
        #expect(rows.contains(ReportRow(.body, "Total spent", trailing: "$66.00")))
        #expect(!rows.contains { $0.leading == "Museum tickets refund" && $0.trailing == "$24.00" })
    }

    @Test func theCSVKeepsTheRefundNegative() {
        let refund = expense("Museum tickets refund", -2400, day: 11, paidBy: sam, among: [me, sam])
        let group = SplitGroup(name: "Lisbon Trip", currencyCode: "USD", memberIDs: [me.id, sam.id])
        let snapshot = GroupExportSnapshot(group: group, people: [me, sam], expenses: [refund], payments: [], exportedAt: utcDate(2026, 5, 20))
        let text = GroupCSVExporter.text(for: snapshot, timeZone: TimeZone(identifier: "UTC")!)
        #expect(text.contains(",-24.00,USD"))
        #expect(!text.contains(",24.00,USD"))
    }

    // MARK: Balances

    @Test func aFormerMemberWithADebtIsListedSoBalancesAddUp() {
        let report = report(
            members: [me, sam],
            expenses: [expense("Dinner", 3000, day: 10, paidBy: me, among: [me, sam, priya])]
        )
        let former = report.members.first { $0.name == "Priya" }
        #expect(former?.isFormer == true)
        #expect(former?.amounts == [usdAmount(-1000)])
        let sum = report.members.flatMap(\.amounts).map(\.minorUnits).reduce(0, +)
        #expect(sum == 0)
        #expect(report.rows(locale: english).contains(ReportRow(.body, "Priya (left)", trailing: "owes $10.00")))
    }

    @Test func theTableAddsUpAndMatchesTheBalances() throws {
        let report = refundReport
        let table = try #require(report.people.first)
        #expect(report.people.count == 1)
        #expect(table.hasPayments)
        #expect(table.total(\.net).minorUnits == 0)
        #expect(table.total(\.settled).minorUnits == 0)
        #expect(table.total(\.paid) == usdAmount(6600))
        #expect(table.total(\.share) == usdAmount(6600))
        let byName = Dictionary(uniqueKeysWithValues: report.members.map { ($0.name, $0.amounts.first?.minorUnits ?? 0) })
        for line in table.lines {
            #expect(line.net.minorUnits == byName[line.name], "\(line.name)")
            #expect(line.net.minorUnits == line.paid.minorUnits - line.share.minorUnits + line.settled.minorUnits)
        }
        let rows = report.rows(locale: english)
        #expect(rows.contains(ReportRow(.columns, "", columns: ["Paid", "Share", "Settled", "Net"])))
        #expect(rows.contains { $0.style == .tableTotal && $0.columns.last == "$0.00" })
    }

    // MARK: Paper

    @Test(arguments: [
        ("en_US", true), ("en_CA", true), ("es_MX", true), ("fil_PH", true),
        ("en_GB", false), ("de_DE", false), ("fr_FR", false), ("en_IN", false), ("ja_JP", false)
    ])
    func paperFollowsTheRegion(identifier: String, isLetter: Bool) {
        let size = GroupPDFRenderer.paperSize(for: Locale(identifier: identifier))
        #expect(size == (isLetter ? GroupPDFRenderer.letter : GroupPDFRenderer.a4))
    }

    @Test func aBritishExportIsPrintedOnA4() throws {
        let report = refundReport
        let document = try #require(PDFDocument(data: GroupPDFRenderer.data(for: report, locale: Locale(identifier: "en_GB"))))
        let size = try #require(document.page(at: 0)?.bounds(for: .mediaBox).size)
        #expect(Int(size.width.rounded()) == 595)
        #expect(Int(size.height.rounded()) == 842)
    }

    // MARK: Pages

    private var longReport: GroupReport {
        let many = (0..<130).map { index in
            expense("Item \(index)", 100 + Int64(index), day: 1 + index % 28, paidBy: index.isMultiple(of: 3) ? sam : me, among: [me, sam, priya])
        }
        return report(members: [me, sam, priya], expenses: many)
    }

    @Test func headingsStayWithTheirFirstRowAndCaptionsWithTheirLine() {
        let rows = longReport.rows(locale: english)
        for available in [120, 300, GroupPDFRenderer.a4.height - 130] as [CGFloat] {
            let pages = ReportLayout.pages(rows, available: available, height: GroupPDFRenderer.height(of:))
            #expect(pages.count > 1)
            for page in pages {
                guard let first = page.first, let last = page.last else {
                    Issue.record("empty page")
                    continue
                }
                #expect(![.heading, .columns, .title].contains(rows[last.row].style), "page ends with \(rows[last.row].leading)")
                #expect(![.caption, .tableTotal, .spacer].contains(rows[first.row].style), "page starts with \(rows[first.row].leading)")
                #expect(page.allSatisfy { $0.y + GroupPDFRenderer.height(of: rows[$0.row]) <= available + 0.5 })
            }
            let placed = pages.flatMap { $0.map(\.row) }.filter { rows[$0].style != .spacer }
            let expected = rows.indices.filter { rows[$0].style != .spacer }
            #expect(placed == expected)
        }
    }

    @Test func aHundredExpensesRunOntoNumberedPages() throws {
        let document = try #require(PDFDocument(data: GroupPDFRenderer.data(for: longReport, locale: english)))
        #expect(document.pageCount > 1)
        for index in 0..<document.pageCount {
            let text = document.page(at: index)?.string ?? ""
            #expect(text.contains("Lisbon Trip · page \(index + 1) of \(document.pageCount)"), "page \(index + 1)")
        }
        let all = document.string ?? ""
        #expect(all.contains("Item 0"))
        #expect(all.contains("Item 129"))
    }
}
