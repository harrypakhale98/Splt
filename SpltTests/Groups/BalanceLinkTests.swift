import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Balance link")
struct BalanceLinkTests {
    private let maya = Person(
        id: PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!), name: "Maya",
        contactHint: "maya@example.com", kind: .me, claimedByCloudUserID: "_cloudUserMaya123"
    )
    private let leo = Person(
        id: PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!), name: "Leo",
        contactHint: "+44 7700 900123"
    )
    private let priya = Person(id: PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000A3")!), name: "Priya")
    private let sam = Person(id: PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000A4")!), name: "Sam")

    private var people: [PersonID: Person] {
        [maya.id: maya, leo.id: leo, priya.id: priya, sam.id: sam]
    }

    private var group: SplitGroup {
        SplitGroup(
            name: "Lisbon trip", currencyCode: "EUR", memberIDs: [maya.id, leo.id, priya.id, sam.id],
            tripStart: utcDate(2026, 11, 7), tripEnd: utcDate(2026, 11, 14)
        )
    }

    private func euros(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "EUR") }

    private func expense(_ title: String, _ cents: Int64, day: Int, paidBy payer: Person, among members: [Person]) -> Expense {
        Expense(
            title: title, total: euros(cents), date: utcDate(2026, 11, day), paidBy: payer.id,
            split: .equal(participants: Set(members.map(\.id)))
        )
    }

    private var expenses: [Expense] {
        let everyone = [maya, leo, priya, sam]
        return (1...12).map { day in
            expense("Day \(day) dinner", 4000 + Int64(day) * 100, day: day, paidBy: everyone[day % 4], among: everyone)
        }
    }

    private func snapshot(includesExpenses: Bool = true, memberIDs: [PersonID]? = nil) -> BalanceSnapshot {
        var group = group
        if let memberIDs { group.memberIDs = memberIDs }
        let ledger = Ledger(expenses: expenses, payments: [])
        return BalanceSnapshot(
            group: group, me: maya.id, people: people, expenses: expenses,
            balances: GroupBalances(groupID: group.id, ledger: ledger, simplifiesDebts: true),
            includesExpenses: includesExpenses, now: utcDate(2026, 11, 10, hour: 18),
            calendar: GroupsTestCalendar.utc
        )
    }

    private func json(_ snapshot: BalanceSnapshot) throws -> String {
        let fragment = try BalanceLink.fragment(for: snapshot)
        let packed = try #require(BalanceLink.data(base64URL: fragment))
        return String(decoding: try BalanceLink.inflate(packed), as: UTF8.self)
    }

    // MARK: Format

    @Test func roundTripsThroughTheLink() throws {
        let original = snapshot()
        let url = try BalanceLink.url(for: original)
        #expect(url.absoluteString.hasPrefix("https://harrypakhale98.github.io/Splt/b/#"))
        let decoded = try BalanceLink.snapshot(fromFragment: try #require(url.fragment))
        #expect(decoded == original)
    }

    @Test func carriesAVersion() throws {
        let text = try json(snapshot())
        #expect(text.contains("\"v\":1"))

        let future = text.replacingOccurrences(of: "\"v\":1", with: "\"v\":2")
        #expect(throws: BalanceSnapshot.FormatError.unsupportedVersion(2)) {
            try JSONDecoder().decode(BalanceSnapshot.self, from: Data(future.utf8))
        }
    }

    @Test func leavesOutIdsAndContactDetails() throws {
        let text = try json(snapshot())
        for person in people.values {
            #expect(!text.localizedCaseInsensitiveContains(person.id.rawValue.uuidString))
        }
        #expect(!text.localizedCaseInsensitiveContains(group.id.rawValue.uuidString))
        for expense in expenses {
            #expect(!text.localizedCaseInsensitiveContains(expense.id.rawValue.uuidString))
        }
        #expect(!text.contains("maya@example.com"))
        #expect(!text.contains("7700"))
        #expect(!text.contains("_cloudUserMaya123"))
    }

    @Test func rejectsIndexesThatPointNowhere() throws {
        let text = try json(snapshot()).replacingOccurrences(of: "\"s\":0", with: "\"s\":9")
        #expect(throws: BalanceSnapshot.FormatError.self) {
            try JSONDecoder().decode(BalanceSnapshot.self, from: Data(text.utf8))
        }
        #expect(throws: (any Error).self) { try BalanceLink.snapshot(fromFragment: "not*base64") }
    }

    // MARK: Content

    @Test func showsWhoPaysWhomAsTheGroupDoes() throws {
        let built = snapshot()
        let balances = GroupBalances(groupID: group.id, ledger: Ledger(expenses: expenses, payments: []), simplifiesDebts: true)
        let order = [maya.id, leo.id, priya.id, sam.id]
        let expected = balances.suggestedSettlements.map {
            BalanceSnapshot.Transfer(
                from: order.firstIndex(of: $0.debtor)!, to: order.firstIndex(of: $0.creditor)!, amount: $0.amount.minorUnits
            )
        }
        #expect(built.transfers == expected)
        #expect(built.members.map(\.name) == ["Maya", "Leo", "Priya", "Sam"])
        #expect(built.sharedBy == 0)
        #expect(built.tripDays == ["2026-11-07", "2026-11-14"])
        #expect(built.currencies == [.init(code: "EUR", digits: 2)])
    }

    @Test func keepsTheTenLatestExpensesWhenAsked() throws {
        let built = snapshot()
        let lines = try #require(built.expenses)
        #expect(lines.count == 10)
        #expect(lines.first?.title == "Day 12 dinner")
        #expect(lines.first?.day == "2026-11-12")
        #expect(lines.first?.shares.map(\.amount).reduce(0, +) == lines.first?.total)
        #expect(snapshot(includesExpenses: false).expenses == nil)
    }

    @Test func marksSomeoneWhoLeftButStillOwes() throws {
        let built = snapshot(memberIDs: [maya.id, leo.id, priya.id])
        let sam = try #require(built.members.first { $0.name == "Sam" })
        #expect(sam.hasLeft)
        #expect(!built.members[0].hasLeft)
    }

    // MARK: Size

    @Test func aLargeGroupStillFits() throws {
        let large = Self.largeSnapshot(members: 30)
        let url = try BalanceLink.url(for: large)
        let fragment = try #require(url.fragment)
        #expect(fragment.count <= BalanceLink.maxFragmentLength)
        let decoded = try BalanceLink.snapshot(fromFragment: fragment)
        #expect(decoded.members.count == 30)
        #expect(decoded.expenses?.count == 10)
    }

    @Test func dropsTheOldestExpensesBeforeGivingUp() throws {
        let huge = Self.largeSnapshot(members: 150)
        #expect(try BalanceLink.fragment(for: huge).count > BalanceLink.maxFragmentLength)
        let url = try BalanceLink.url(for: huge)
        let decoded = try BalanceLink.snapshot(fromFragment: try #require(url.fragment))
        let kept = try #require(decoded.expenses)
        #expect(kept.count < 10)
        #expect(kept == Array(huge.expenses!.prefix(kept.count)))

        #expect(throws: BalanceLink.LinkError.tooLarge) {
            try BalanceLink.url(for: Self.largeSnapshot(members: 800))
        }
    }

    /// A group with long, varied names and amounts that don't repeat, so it compresses badly.
    static func largeSnapshot(members count: Int) -> BalanceSnapshot {
        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let syllables = ["ka", "lo", "mi", "ra", "su", "te", "vin", "do", "xa", "be", "nor", "phi", "zu", "qe"]
        func word(_ length: Int) -> String {
            (0..<length).map { _ in syllables[next(syllables.count)] }.joined().capitalized
        }
        let members = (0..<count).map { index in
            BalanceSnapshot.Member(name: "\(word(3)) \(word(4))", colorIndex: index % 12, paid: Int64(next(900_000)))
        }
        let transfers = (1..<count).map { index in
            BalanceSnapshot.Transfer(from: index, to: next(index), amount: Int64(next(90_000)))
        }
        let expenses = (0..<10).map { index in
            BalanceSnapshot.ExpenseLine(
                title: "\(word(4)) \(word(5)) \(word(3))", day: "2026-11-\(String(format: "%02d", 20 - index))",
                currency: 0, total: Int64(next(900_000)),
                payers: [.init(person: next(count), amount: Int64(next(900_000)))],
                shares: (0..<count).map { .init(person: $0, amount: Int64(next(30_000))) }
            )
        }
        return BalanceSnapshot(
            groupName: "Summer house with everyone from work", tripDays: ["2026-11-01", "2026-11-20"],
            currencies: [.init(code: "EUR", digits: 2)], members: members, transfers: transfers,
            expenses: expenses, sharedBy: 0, createdAt: Date(timeIntervalSince1970: 1_794_336_000)
        )
    }

    // MARK: Fixtures for the web page

    /// The snapshot `docs/b/test/decode-fixture.mjs` expects, written beside it so the page's decoder
    /// is checked against what the app actually produces.
    static var fixture: BalanceSnapshot {
        BalanceSnapshot(
            groupName: "Lisbon trip <b>", tripDays: ["2026-11-07", "2026-11-14"],
            currencies: [.init(code: "EUR", digits: 2), .init(code: "JPY", digits: 0)],
            members: [
                .init(name: "Maya", colorIndex: 0, paid: 9600),
                .init(name: "Leo", colorIndex: 5, paid: 2400),
                .init(name: "Priya", colorIndex: 10, paid: 0),
                .init(name: "Zoë Ångström", colorIndex: 2, paid: 3840, hasLeft: true)
            ],
            transfers: [
                .init(from: 1, to: 0, amount: 8420),
                .init(from: 2, to: 0, amount: 1500),
                .init(from: 2, to: 3, amount: 1200, currency: 1)
            ],
            expenses: [
                .init(
                    title: "Dinner at Taberna", day: "2026-11-07", currency: 0, total: 9600,
                    payers: [.init(person: 0, amount: 9600)],
                    shares: (0..<4).map { .init(person: $0, amount: 2400) }
                ),
                .init(
                    title: "<img src=x onerror=alert(1)>", day: "2026-11-06", currency: 1, total: 1200,
                    payers: [.init(person: 3, amount: 1200)], shares: [.init(person: 2, amount: 1200)]
                )
            ],
            sharedBy: 0,
            createdAt: Date(timeIntervalSince1970: 1_794_336_000)
        )
    }

    @Test func writesFixturesForTheWebPage() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/b/test")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let small = try BalanceLink.url(for: Self.fixture)
        let large = try BalanceLink.url(for: Self.largeSnapshot(members: 30))
        try (small.absoluteString + "\n").write(to: folder.appending(path: "fixture.txt"), atomically: true, encoding: .utf8)
        try (large.absoluteString + "\n").write(to: folder.appending(path: "fixture-large.txt"), atomically: true, encoding: .utf8)
        #expect(try BalanceLink.snapshot(fromFragment: try #require(small.fragment)) == Self.fixture)
    }
}
