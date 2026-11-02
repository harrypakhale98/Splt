import Foundation
import PDFKit
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Group export flow")
struct GroupExportFlowTests {
    private func makeModel(_ fixture: Fixture) -> GroupSettingsViewModel {
        let model = GroupSettingsViewModel(
            groupID: fixture.group.id, services: fixture.services, leftGroups: isolatedLeftGroups(),
            now: { utcDate(2026, 5, 20) }
        )
        model.locale = GroupsTestCalendar.english
        return model
    }

    @Test func theReportListsBalancesTransfersAndExpenses() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let text = try makeModel(fixture).report().plainText(locale: GroupsTestCalendar.english)
        #expect(text.contains("Flat"))
        #expect(text.contains("Dinner  $30.00"))
        #expect(text.contains("Sam  owes $10.00"))
        #expect(text.contains("Me  is owed $20.00"))
        #expect(text.contains("Sam pays Me  $10.00"))
        #expect(text.contains("Total spent  $30.00"))
    }

    @Test func theReportOfAnEmptyGroupIsCalm() throws {
        let fixture = try Fixture()
        let text = try makeModel(fixture).report().plainText(locale: GroupsTestCalendar.english)
        #expect(text.contains("Everyone is settled up"))
        #expect(text.contains("No expenses"))
    }

    @Test func deletedExpensesAreLeftOutOfTheReport() throws {
        let fixture = try Fixture()
        let mistake = try fixture.addExpense("Mistake")
        try fixture.addExpense("Real")
        try fixture.services.expenses.delete(id: mistake.id)
        let text = try makeModel(fixture).report().plainText(locale: GroupsTestCalendar.english)
        #expect(text.contains("Real"))
        #expect(!text.contains("Mistake"))
    }

    private func exportDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("splt-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func readyURL(_ model: GroupSettingsViewModel, _ kind: GroupExportKind) throws -> URL {
        guard case .ready(let url) = model.exportState(kind) else {
            throw ExportNotReady(state: model.exportState(kind))
        }
        return url
    }

    private struct ExportNotReady: Error { var state: GroupExportState }

    @Test func exportsStartIdleAndNothingIsBuiltUntilAsked() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        for kind in GroupExportKind.allCases {
            #expect(model.exportState(kind) == .idle)
        }
    }

    @Test func exportWritesAReadableSpreadsheet() async throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let model = makeModel(fixture)
        model.exportDirectory = exportDirectory()
        await model.prepareExport(.csv)

        let url = try readyURL(model, .csv)
        #expect(url.lastPathComponent == "Flat.csv")
        let csv = try String(contentsOf: url, encoding: .utf8)
        #expect(csv.hasPrefix("Date,Description,Category,Cost,Currency,Me,Sam,Priya"))
        #expect(csv.contains("Dinner"))
        #expect(csv.contains("Total balance"))
        #expect(model.exportState(.pdf) == .idle)
    }

    @Test func exportWritesAReadablePDF() async throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let model = makeModel(fixture)
        model.exportDirectory = exportDirectory()
        await model.prepareExport(.pdf)

        let url = try readyURL(model, .pdf)
        #expect(url.lastPathComponent == "Flat.pdf")
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 1)
        let text = document.string ?? ""
        #expect(text.contains("Flat"))
        #expect(text.contains("Dinner"))
    }

    @Test func exportWritesJSONThatReadsBack() async throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        let model = makeModel(fixture)
        model.exportDirectory = exportDirectory()
        await model.prepareExport(.json)

        let url = try readyURL(model, .json)
        #expect(url.lastPathComponent == "Flat.json")
        let document = try GroupJSONExporter.decode(Data(contentsOf: url))
        #expect(document.expenses.map(\.title) == ["Dinner"])
    }

    @Test func aLongReportContinuesOnMorePages() async throws {
        let fixture = try Fixture()
        for index in 0..<120 {
            try fixture.addExpense("Expense \(index)", cents: 100)
        }
        let model = makeModel(fixture)
        model.exportDirectory = exportDirectory()
        await model.prepareExport(.pdf)
        let document = try #require(PDFDocument(url: try readyURL(model, .pdf)))
        #expect(document.pageCount > 1)
        #expect((document.string ?? "").contains("Expense 119"))
    }

    @Test func aFailedExportSaysSoAndRetrySucceeds() async throws {
        let fixture = try Fixture()
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("splt-tests-\(UUID().uuidString)")
        try Data().write(to: blocker)
        let model = makeModel(fixture)

        model.exportDirectory = blocker
        await model.prepareExport(.csv)
        guard case .failed(let message) = model.exportState(.csv) else {
            Issue.record("expected a failure, got \(model.exportState(.csv))")
            return
        }
        #expect(message.contains("Try again"))

        model.exportDirectory = exportDirectory()
        await model.prepareExport(.csv)
        _ = try readyURL(model, .csv)
    }

    @Test func exportingAGroupThatIsGoneFails() async throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.exportDirectory = exportDirectory()
        _ = model.delete()
        await model.prepareExport(.pdf)
        guard case .failed(let message) = model.exportState(.pdf) else {
            Issue.record("expected a failure, got \(model.exportState(.pdf))")
            return
        }
        #expect(message.contains("no longer available"))
    }

    @Test func changingTheGroupDiscardsPreparedFiles() async throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.exportDirectory = exportDirectory()
        await model.prepareExport(.csv)
        _ = try readyURL(model, .csv)

        model.name = "Renamed"
        try model.save()
        #expect(model.exportState(.csv) == .idle)
    }

    @Test func fileNamesAreSafe() {
        #expect(GroupExportFile.fileName(for: "Trip: Rome/Paris") == "Trip- Rome-Paris")
        #expect(GroupExportFile.fileName(for: "  ") == "Group")
        #expect(GroupExportFile.fileName(for: "Flat 4B") == "Flat 4B")
    }

    @Test func eachKindHasItsExtension() {
        #expect(GroupExportKind.csv.fileExtension == "csv")
        #expect(GroupExportKind.json.fileExtension == "json")
        #expect(GroupExportKind.pdf.fileExtension == "pdf")
    }
}
