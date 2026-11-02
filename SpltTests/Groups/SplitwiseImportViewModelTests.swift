import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Splitwise import flow")
struct SplitwiseImportViewModelTests {
    private let fileName = "Weekend Trip_2025-03-14_export.csv"

    private let csv = """
        Date,Description,Category,Cost,Currency,Me,Sam,Alex
        2025-03-14,Dinner,Dining out,30.00,USD,20.00,-10.00,-10.00
        2025-03-15,Taxi,Taxi,12.00,USD,-4.00,8.00,-4.00
        not a date,Broken,General,10.00,USD,5.00,-5.00,0.00
        2025-03-16,Alex paid Me,Payment,5.00,USD,-5.00,0.00,5.00
        ,Total balance,,,USD,11.00,-2.00,-9.00
        """

    private func isolatedHistory() -> SplitwiseImportHistory {
        SplitwiseImportHistory(defaults: UserDefaults(suiteName: "splt.tests.\(UUID().uuidString)")!)
    }

    private func makeModel(
        _ fixture: Fixture, history: SplitwiseImportHistory? = nil
    ) -> SplitwiseImportViewModel {
        SplitwiseImportViewModel(
            services: fixture.services, history: history ?? isolatedHistory(), defaultCurrencyCode: "EUR"
        )
    }

    private func groupCount(_ fixture: Fixture) throws -> Int {
        try fixture.services.groups.groups(includeArchived: true).count
    }

    // MARK: Preview

    @Test func previewShowsWhatIsInTheFile() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        #expect(model.step == .instructions)
        #expect(model.load(text: csv, fileName: fileName))

        #expect(model.step == .preview)
        #expect(model.groupName == "Weekend Trip")
        #expect(model.currencyCode == "USD")
        let preview = try #require(model.preview)
        #expect(preview.expenseCount == 2)
        #expect(preview.paymentCount == 1)
        #expect(preview.totals == [usdAmount(4200)])
        #expect(model.mappings.map(\.name) == ["Me", "Sam", "Alex"])
    }

    @Test func skippedRowsComeWithALineAndAReason() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.load(text: csv, fileName: fileName)
        let warnings = try #require(model.preview?.warnings)
        #expect(warnings.count == 1)
        #expect(warnings.first?.line == 4)
        #expect(warnings.first?.message == "Unreadable date.")
    }

    @Test func peopleAreMatchedByNameAndOthersAreNew() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.load(text: csv, fileName: fileName)
        #expect(model.choice(for: "Me") == .existing(fixture.me.id))
        #expect(model.choice(for: "Sam") == .existing(fixture.sam.id))
        #expect(model.choice(for: "Alex") == .newPerson)
        #expect(model.candidates.first?.id == fixture.me.id)
        #expect(model.mappingProblem == nil)
        #expect(model.canImport)
    }

    @Test func theCommonCurrencyBecomesTheGroupCurrency() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.load(text: """
            Date,Description,Category,Cost,Currency,Me,Sam
            2025-03-14,Lunch,Dining out,10.00,EUR,5.00,-5.00
            2025-03-15,Coffee,Dining out,4.00,EUR,2.00,-2.00
            2025-03-16,Ramen,Dining out,1000,JPY,500,-500
            """, fileName: "Trip.csv")
        #expect(model.currencyCode == "EUR")
        #expect(model.preview?.totals.count == 2)
    }

    // MARK: Bad files

    @Test func badFilesChangeNothing() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        let groupsBefore = try groupCount(fixture)
        let peopleBefore = try fixture.services.people.allPeople().count

        #expect(!model.load(text: "", fileName: "empty.csv"))
        #expect(model.errorMessage != nil)
        #expect(!model.load(text: "just some words\nnot a table", fileName: "words.csv"))
        #expect(!model.load(text: "Date,Description,Category,Cost,Currency,Me,Sam", fileName: "header.csv"))
        #expect(!model.load(text: """
            Date,Description,Category,Cost,Currency,Me,Sam
            nope,Lunch,Dining out,10.00,EUR,5.00,-5.00
            """, fileName: "bad rows.csv"))

        #expect(model.step == .instructions)
        #expect(model.preview == nil)
        #expect(!model.canImport)
        #expect(model.performImport() == nil)
        #expect(try groupCount(fixture) == groupsBefore)
        #expect(try fixture.services.people.allPeople().count == peopleBefore)
    }

    @Test func aGoodFileClearsAnEarlierError() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.load(text: "nothing", fileName: "x.csv")
        #expect(model.errorMessage != nil)
        #expect(model.load(text: csv, fileName: fileName))
        #expect(model.errorMessage == nil)
    }

    @Test func filesAreReadFromDisk() throws {
        let fixture = try Fixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        try ("\u{FEFF}" + csv.replacingOccurrences(of: "\n", with: "\r\n")).write(to: url, atomically: true, encoding: .utf8)

        let model = makeModel(fixture)
        #expect(model.loadFile(at: url))
        #expect(model.preview?.expenseCount == 2)
        #expect(model.groupName == "Weekend Trip")

        let missing = makeModel(fixture)
        #expect(!missing.loadFile(at: folder.appendingPathComponent("missing.csv")))
        #expect(missing.errorMessage != nil)
    }

    @Test func unreadableBytesAreRejected() {
        #expect(throws: SplitwiseFile.Unreadable.self) { try SplitwiseFile.text(from: Data([0x00, 0x01, 0x02])) }
        #expect((try? SplitwiseFile.text(from: Data("caf\u{E9}".utf8))) == "caf\u{E9}")
    }

    // MARK: Importing

    @Test func importCreatesTheGroupWithEverythingInIt() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.load(text: csv, fileName: fileName)
        let peopleBefore = try fixture.services.people.allPeople().count

        let id = try #require(model.performImport())
        let group = try #require(try fixture.services.groups.group(id: id))
        #expect(group.name == "Weekend Trip")
        #expect(group.currencyCode == "USD")
        #expect(group.memberIDs.count == 3)
        #expect(group.memberIDs.starts(with: [fixture.me.id, fixture.sam.id]))

        #expect(try fixture.services.expenses.expenses(in: id).count == 2)
        #expect(try fixture.services.payments.payments(in: id).count == 1)
        let balances = try fixture.services.groups.balances(for: id)
        #expect(balances.net(for: fixture.me.id) == [usdAmount(1100)])
        #expect(balances.net(for: fixture.sam.id) == [usdAmount(-200)])

        let people = try fixture.services.people.allPeople()
        #expect(people.count == peopleBefore + 1)
        let alex = try #require(people.first { $0.name == "Alex" })
        #expect(alex.isPlaceholder)
        #expect(balances.net(for: alex.id) == [usdAmount(-900)])

        let imported = try fixture.services.activity.entries(in: id, limit: 50).filter {
            if case .expensesImported = $0.event { return true }
            return false
        }
        #expect(imported.count == 1)
    }

    @Test func aSplitwiseMemberCanBeMatchedToADifferentFriend() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.load(text: csv, fileName: fileName)
        model.setChoice(.existing(fixture.priya.id), for: "Alex")
        let peopleBefore = try fixture.services.people.allPeople().count

        let id = try #require(model.performImport())
        let group = try #require(try fixture.services.groups.group(id: id))
        #expect(Set(group.memberIDs) == [fixture.me.id, fixture.sam.id, fixture.priya.id])
        #expect(try fixture.services.people.allPeople().count == peopleBefore)
        #expect(try fixture.services.groups.balances(for: id).net(for: fixture.priya.id) == [usdAmount(-900)])
    }

    @Test func aNewPersonNeverTakesOverAMatchedPersonsName() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.load(text: csv, fileName: fileName)
        model.setChoice(.existing(fixture.sam.id), for: "Alex")
        model.setChoice(.newPerson, for: "Sam")
        #expect(model.resolvedNames(me: fixture.me)["Sam"] == "Sam (Splitwise)")
        #expect(model.resolvedNames(me: fixture.me)["Alex"] == "Sam")

        let id = try #require(model.performImport())
        let balances = try fixture.services.groups.balances(for: id)
        #expect(balances.net(for: fixture.sam.id) == [usdAmount(-900)])
        let stranger = try #require(try fixture.services.people.allPeople().first { $0.name == "Sam (Splitwise)" })
        #expect(balances.net(for: stranger.id) == [usdAmount(-200)])
    }

    @Test func matchingTwoMembersToOnePersonIsRefused() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.load(text: csv, fileName: fileName)
        model.setChoice(.existing(fixture.sam.id), for: "Alex")
        model.setChoice(.existing(fixture.sam.id), for: "Sam")
        #expect(model.mappingProblem?.contains("Sam") == true)
        #expect(!model.canImport)
        let before = try groupCount(fixture)
        #expect(model.performImport() == nil)
        #expect(try groupCount(fixture) == before)
    }

    @Test func twoMatchedPeopleWithTheSameNameAreRefused() throws {
        let fixture = try Fixture()
        let twin = Person(name: "me")
        try fixture.services.people.add(twin)
        let model = makeModel(fixture)
        model.load(text: csv, fileName: fileName)
        model.setChoice(.existing(twin.id), for: "Alex")
        #expect(model.mappingProblem != nil)
        #expect(!model.canImport)
    }

    @Test func aBlankGroupNameCannotBeImported() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.load(text: csv, fileName: fileName)
        model.groupName = "   "
        #expect(!model.canImport)
        model.groupName = "Trip"
        #expect(model.canImport)
    }

    @Test func importingWorksWithoutAnExistingProfile() throws {
        let services = try DataServices.inMemory()
        let model = SplitwiseImportViewModel(services: services, history: isolatedHistory(), defaultCurrencyCode: "USD")
        model.load(text: csv, fileName: fileName)
        let id = try #require(model.performImport())
        let me = try #require(try services.people.me())
        #expect(try services.groups.group(id: id)?.memberIDs.first == me.id)
    }

    // MARK: Running twice

    @Test func theSameFileIsNotImportedTwice() throws {
        let fixture = try Fixture()
        let history = isolatedHistory()
        let first = makeModel(fixture, history: history)
        first.load(text: csv, fileName: fileName)
        let id = try #require(first.performImport())
        let groupsAfterFirst = try groupCount(fixture)
        let expensesAfterFirst = try fixture.services.expenses.expenses(in: id).count

        let second = makeModel(fixture, history: history)
        #expect(second.load(text: csv.replacingOccurrences(of: "\n", with: "\r\n"), fileName: "again.csv"))
        #expect(second.existingGroupID == id)
        #expect(!second.canImport)
        #expect(second.performImport() == nil)
        #expect(try groupCount(fixture) == groupsAfterFirst)
        #expect(try fixture.services.expenses.expenses(in: id).count == expensesAfterFirst)
    }

    @Test func aDeletedImportCanBeImportedAgain() throws {
        let fixture = try Fixture()
        let history = isolatedHistory()
        let first = makeModel(fixture, history: history)
        first.load(text: csv, fileName: fileName)
        let id = try #require(first.performImport())
        try fixture.services.groups.delete(id: id)

        let second = makeModel(fixture, history: history)
        second.load(text: csv, fileName: fileName)
        #expect(second.existingGroupID == nil)
        #expect(second.canImport)
    }

    @Test func aChangedFileIsANewImport() throws {
        let fixture = try Fixture()
        let history = isolatedHistory()
        let first = makeModel(fixture, history: history)
        first.load(text: csv, fileName: fileName)
        _ = first.performImport()

        let second = makeModel(fixture, history: history)
        second.load(text: csv + "\n2025-03-20,Lunch,Dining out,10.00,USD,5.00,-5.00,0.00", fileName: fileName)
        #expect(second.existingGroupID == nil)
        #expect(second.canImport)
    }

    @Test func goingBackKeepsNothing() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.load(text: csv, fileName: fileName)
        model.chooseAnotherFile()
        #expect(model.step == .instructions)
        #expect(model.preview == nil)
        #expect(!model.canImport)
    }
}

@Suite("Splitwise files")
struct SplitwiseFileTests {
    @Test func groupNamesComeFromTheFileName() {
        #expect(SplitwiseFile.groupName(fromFileName: "Weekend Trip_2025-03-14_export.csv") == "Weekend Trip")
        #expect(SplitwiseFile.groupName(fromFileName: "Flat_4B_2025-03-14_export.csv") == "Flat 4B")
        #expect(SplitwiseFile.groupName(fromFileName: "Lisbon.csv") == "Lisbon")
        #expect(SplitwiseFile.groupName(fromFileName: "_export.csv") == "Splitwise Import")
        #expect(SplitwiseFile.groupName(fromFileName: "") == "Splitwise Import")
    }

    @Test func fingerprintsIgnoreLineEndingsAndTheByteOrderMark() {
        let text = "a,b\n1,2\n"
        #expect(SplitwiseFile.fingerprint(text) == SplitwiseFile.fingerprint("\u{FEFF}a,b\r\n1,2\r\n"))
        #expect(SplitwiseFile.fingerprint(text) != SplitwiseFile.fingerprint("a,b\n1,3\n"))
    }

    @Test func renamingChangesOnlyTheMemberColumns() throws {
        let text = "Date,Description,Category,Cost,Currency,Ana,Ben\n2025-03-14,\"Sam, Ana\",General,10.00,USD,5.00,-5.00\n"
        let renamed = try #require(SplitwiseFile.renamingMembers(in: text, to: ["Ana": "Anastasia", "Ben": "Ben"]))
        let rows = CSVText.rows(renamed)
        #expect(rows[0] == ["Date", "Description", "Category", "Cost", "Currency", "Anastasia", "Ben"])
        #expect(rows[1][1] == "Sam, Ana")
        #expect(SplitwiseFile.renamingMembers(in: "no header here", to: [:]) == nil)
    }

    @Test func historyRemembersFiles() {
        let history = SplitwiseImportHistory(defaults: UserDefaults(suiteName: "splt.tests.\(UUID().uuidString)")!)
        let id = GroupID()
        #expect(history.groupID(forFingerprint: "abc") == nil)
        history.record(fingerprint: "abc", groupID: id)
        #expect(history.groupID(forFingerprint: "abc") == id)
    }
}
