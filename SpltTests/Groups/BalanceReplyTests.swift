import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Balance reply format")
struct BalanceReplyFormatTests {
    static let token = "Qm9vdHN0cmFwUmVwbHlDb2Rl"

    static func expense(
        author: Int = 1, payer: Int = 1, participants: [Int] = [0, 1, 2], amount: Int64 = 3000,
        code: String = "USD", digits: Int = 2, title: String = "Taxi", day: String = "2026-11-11"
    ) -> BalanceReply {
        BalanceReply(
            token: token, groupName: "Flat", author: author, names: [0: "Me", 1: "Sam", 2: "Priya"],
            currencyCode: code, digits: digits, amount: amount,
            kind: .expense(title: title, day: day, payer: payer, participants: participants),
            createdAt: Date(timeIntervalSince1970: 1_794_427_200)
        )
    }

    static func payment(from: Int = 1, to: Int = 0, amount: Int64 = 1000) -> BalanceReply {
        BalanceReply(
            token: token, groupName: "Flat", author: from, names: [0: "Me", 1: "Sam"],
            currencyCode: "USD", digits: 2, amount: amount, kind: .payment(from: from, to: to),
            createdAt: Date(timeIntervalSince1970: 1_794_427_200)
        )
    }

    @Test func roundTripsThroughAFragment() throws {
        for reply in [Self.expense(), Self.payment()] {
            #expect(try BalanceReply(fragment: try reply.fragment()) == reply)
        }
    }

    /// The page writes this file; see docs/b/test/decode-fixture.mjs.
    @Test func readsAReplyThePageMade() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/b/test/reply-fixture.txt")
        let link = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = "#r."
        let range = try #require(link.range(of: marker))
        let reply = try BalanceReply(fragment: String(link[range.upperBound...]))
        #expect(reply.groupName == "Lisbon trip")
        #expect(reply.author == 1)
        #expect(reply.names == [0: "Maya", 1: "Leo", 2: "Priya"])
        #expect(reply.money == Money(minorUnits: 2400, currencyCode: "EUR"))
        #expect(reply.kind == .expense(title: "Taxi <b>", day: "2026-11-11", payer: 1, participants: [0, 1, 2]))
        #expect(reply.createdAt == Date(timeIntervalSince1970: 1794428100))
        #expect(BalanceSnapshot.isReplyToken(reply.token))
    }

    @Test func refusesRepliesThatDontAddUp() throws {
        let bad: [BalanceReply] = [
            Self.expense(participants: []),
            Self.expense(participants: [0, 0]),
            Self.expense(amount: 0),
            Self.expense(amount: -5),
            Self.expense(code: "JPY", digits: 2),
            Self.expense(code: "QQQ"),
            Self.expense(title: "   "),
            Self.expense(day: "2026-02-30"),
            Self.expense(payer: 5_000),
            Self.payment(from: 1, to: 1)
        ]
        for reply in bad {
            let fragment = try reply.fragment()
            #expect(throws: BalanceReply.FormatError.self) { try BalanceReply(fragment: fragment) }
        }
    }

    @Test func refusesBrokenAndFutureLinks() throws {
        #expect(throws: BalanceReply.FormatError.unreadable) { try BalanceReply(fragment: "not a link") }
        #expect(throws: BalanceReply.FormatError.tooLong) {
            try BalanceReply(fragment: String(repeating: "A", count: BalanceReply.maxFragmentLength + 1))
        }
        let text = String(decoding: try JSONEncoder().encode(Self.payment()), as: UTF8.self)
            .replacingOccurrences(of: "\"v\":1", with: "\"v\":2")
        let future = BalanceLink.base64URL(try BalanceLink.deflate(Data(text.utf8)))
        #expect(throws: BalanceReply.FormatError.unsupportedVersion(2)) { try BalanceReply(fragment: future) }
    }

    @Test func flattensNamesAndTitles() throws {
        var reply = Self.expense(title: "Taxi\nto the\u{0}airport")
        reply.names[1] = "Sam\nSmith"
        let back = try BalanceReply(fragment: try reply.fragment())
        #expect(back.kind == .expense(title: "Taxi to the airport", day: "2026-11-11", payer: 1, participants: [0, 1, 2]))
        #expect(back.names[1] == "Sam Smith")
    }

    @Test func readsTheDayAtNoonInTheGivenCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        let date = try #require(Self.expense(day: "2026-11-11").date(calendar: calendar))
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(parts == DateComponents(year: 2026, month: 11, day: 11, hour: 12))
        #expect(Self.payment().date(calendar: calendar) == nil)
    }

    @Test func namesEachReplyTheSameWayEveryTime() throws {
        let fragment = try Self.expense().fragment()
        #expect(BalanceReply.id(ofFragment: fragment) == BalanceReply.id(ofFragment: fragment))
        #expect(BalanceReply.id(ofFragment: fragment) != BalanceReply.id(ofFragment: try Self.payment().fragment()))
        #expect(BalanceReply.id(ofFragment: fragment).count == 32)
    }
}

@Suite("Balance link reply code")
struct BalanceLinkReplyCodeTests {
    @Test func aSnapshotCarriesItsReplyCode() throws {
        let me = Person(name: "Maya", kind: .me)
        let leo = Person(name: "Leo")
        let group = SplitGroup(name: "Flat", currencyCode: "EUR", memberIDs: [me.id, leo.id])
        let snapshot = BalanceSnapshot(
            group: group, me: me.id, people: [me.id: me, leo.id: leo], expenses: [], balances: nil,
            includesExpenses: false, now: Date(timeIntervalSince1970: 1_794_336_000), replyToken: BalanceReplyFormatTests.token
        )
        let decoded = try BalanceLink.snapshot(fromFragment: try BalanceLink.fragment(for: snapshot))
        #expect(decoded.replyToken == BalanceReplyFormatTests.token)
        #expect(decoded == snapshot)

        var crafted = snapshot
        crafted.replyToken = "too short"
        let fragment = try BalanceLink.fragment(for: crafted)
        #expect(throws: BalanceSnapshot.FormatError.invalid("reply")) {
            try BalanceLink.snapshot(fromFragment: fragment)
        }
    }

    @Test func madeCodesAreLongAndDifferent() {
        let codes = (0..<50).map { _ in BalanceReplyStore.makeToken() }
        #expect(Set(codes).count == 50)
        #expect(codes.allSatisfy(BalanceSnapshot.isReplyToken))
        #expect(!BalanceSnapshot.isReplyToken("abc"))
        #expect(!BalanceSnapshot.isReplyToken("ünïcödé-ünïcödé-ünïcödé"))
    }

    /// The order the store keeps has to number people exactly as the link does.
    @Test func memberOrderMatchesTheLinksNumbers() {
        let maya = Person(name: "Maya", kind: .me)
        let leo = Person(name: "Leo")
        let gone = Person(name: "Zoë")
        let group = SplitGroup(name: "Flat", currencyCode: "EUR", memberIDs: [maya.id, leo.id])
        let expenses = [
            Expense(
                groupID: group.id, title: "Old dinner", total: Money(minorUnits: 900, currencyCode: "EUR"),
                date: Date(timeIntervalSince1970: 1_794_000_000), paidBy: gone.id,
                split: .equal(participants: [maya.id, gone.id, leo.id])
            )
        ]
        let people = [maya.id: maya, leo.id: leo, gone.id: gone]
        let order = BalanceSnapshot.memberOrder(group: group, expenses: expenses, balances: nil)
        let withExpenses = BalanceSnapshot(
            group: group, me: maya.id, people: people, expenses: expenses, balances: nil,
            includesExpenses: true, now: Date()
        )
        let without = BalanceSnapshot(
            group: group, me: maya.id, people: people, expenses: expenses, balances: nil,
            includesExpenses: false, now: Date()
        )
        #expect(order.map { people[$0]?.name } == withExpenses.members.map(\.name))
        #expect(Array(order.prefix(without.members.count)).map { people[$0]?.name } == without.members.map(\.name))
    }
}

@Suite("Balance reply store")
struct BalanceReplyStoreTests {
    private func store(now: Date = Date(timeIntervalSince1970: 1_794_336_000)) -> (BalanceReplyStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "splt.tests.replies.\(UUID().uuidString)")!
        return (BalanceReplyStore(defaults: defaults, now: { now }), defaults)
    }

    @Test func keepsOneCodePerGroupAndOrder() {
        let (store, _) = store()
        let group = GroupID()
        let people = [PersonID(), PersonID()]
        let first = store.token(for: group, people: people)
        #expect(store.token(for: group, people: people) == first)
        #expect(store.token(for: group, people: people.reversed()) != first)
        #expect(store.token(for: GroupID(), people: people) != first)
        #expect(store.entry(for: first)?.people == people.map(\.rawValue))
    }

    @Test func forgetsOldLinks() {
        let start = Date(timeIntervalSince1970: 1_794_336_000)
        let (early, defaults) = store(now: start)
        let token = early.token(for: GroupID(), people: [PersonID()])
        let later = BalanceReplyStore(defaults: defaults, now: { start.addingTimeInterval(BalanceReplyStore.lifetime + 60) })
        #expect(early.entry(for: token) != nil)
        #expect(later.entry(for: token) == nil)
    }

    @Test func remembersWhatWasAdded() {
        let (store, _) = store()
        let token = store.token(for: GroupID(), people: [PersonID()])
        #expect(!store.wasAdded("abc", token: token))
        store.markAdded("abc", token: token)
        store.markAdded("abc", token: token)
        #expect(store.wasAdded("abc", token: token))
        #expect(store.entry(for: token)?.added == ["abc"])
        store.markAdded("abc", token: "unknown")
        #expect(!store.wasAdded("abc", token: "unknown"))
    }

    @Test func keepsTheListShort() {
        let (store, _) = store()
        let group = GroupID()
        let first = store.token(for: group, people: [PersonID()])
        for _ in 0..<BalanceReplyStore.maxEntries { store.token(for: group, people: [PersonID()]) }
        #expect(store.entry(for: first) == nil)
    }
}

@MainActor
@Suite("Reviewing a balance reply")
struct ReplyReviewModelTests {
    private func setUp() throws -> (Fixture, BalanceReplyStore, String) {
        let fixture = try Fixture()
        let defaults = UserDefaults(suiteName: "splt.tests.review.\(UUID().uuidString)")!
        let store = BalanceReplyStore(defaults: defaults, now: { fixture.clock.start })
        let token = store.token(for: fixture.group.id, people: [fixture.me.id, fixture.sam.id, fixture.priya.id])
        return (fixture, store, token)
    }

    private func fragment(_ reply: BalanceReply, token: String) throws -> String {
        var reply = reply
        reply.token = token
        return try reply.fragment()
    }

    @Test func addsAnExpenseOnlyAfterReview() throws {
        let (fixture, store, token) = try setUp()
        let packed = try fragment(BalanceReplyFormatTests.expense(), token: token)
        let model = ReplyReviewModel(fragment: packed, services: fixture.services, store: store, now: fixture.clock.start)

        guard case .ready(let proposal) = model.state else {
            Issue.record("expected a proposal, got \(model.state)")
            return
        }
        #expect(proposal.author.id == fixture.sam.id)
        #expect(proposal.me == fixture.me.id)
        #expect(proposal.name(of: fixture.me) == "You")
        if case .expense(_, _, let shares) = proposal.item {
            // in the group's order, each with their part
            #expect(shares.map(\.person.id) == [fixture.me.id, fixture.sam.id, fixture.priya.id])
            #expect(shares.map(\.amount) == [usdAmount(1000), usdAmount(1000), usdAmount(1000)])
        } else {
            Issue.record("expected an expense")
        }
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).isEmpty)

        #expect(model.add() == fixture.group.id)
        let stored = try #require(try fixture.services.expenses.expenses(in: fixture.group.id).first)
        #expect(stored.title == "Taxi")
        #expect(stored.payers == [fixture.sam.id: usdAmount(3000)])
        #expect(stored.split.participants == fixture.everyone)
        #expect(stored.note.contains("Sam"))
        #expect(Calendar.current.dateComponents([.year, .month, .day], from: stored.date)
            == DateComponents(year: 2026, month: 11, day: 11))
        #expect(try fixture.services.people.friendBalance(with: fixture.sam.id).total == [usdAmount(-1000)])
    }

    @Test func addsTheSameReplyOnlyOnce() throws {
        let (fixture, store, token) = try setUp()
        let packed = try fragment(BalanceReplyFormatTests.expense(), token: token)
        _ = ReplyReviewModel(fragment: packed, services: fixture.services, store: store).add()
        let again = ReplyReviewModel(fragment: packed, services: fixture.services, store: store)
        #expect(again.state == .alreadyAdded(groupName: "Flat", group: fixture.group.id))
        #expect(again.add() == nil)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 1)
    }

    @Test func recordsAPayment() throws {
        let (fixture, store, token) = try setUp()
        let packed = try fragment(BalanceReplyFormatTests.payment(from: 1, to: 0), token: token)
        let model = ReplyReviewModel(fragment: packed, services: fixture.services, store: store, now: fixture.clock.start)
        #expect(model.add() == fixture.group.id)
        let payment = try #require(try fixture.services.payments.payments(in: fixture.group.id).first)
        #expect(payment.payer == fixture.sam.id)
        #expect(payment.receiver == fixture.me.id)
        #expect(payment.amount == usdAmount(1000))
        #expect(payment.date <= fixture.clock.start)
    }

    @Test func goesByTheLinksOwnNumbersNotNames() throws {
        let (fixture, store, _) = try setUp()
        // the same group shared in another order: 0 is now Priya
        let token = store.token(for: fixture.group.id, people: [fixture.priya.id, fixture.sam.id, fixture.me.id])
        let packed = try fragment(BalanceReplyFormatTests.expense(author: 0, payer: 0, participants: [0, 2]), token: token)
        let model = ReplyReviewModel(fragment: packed, services: fixture.services, store: store)
        guard case .ready(let proposal) = model.state, case .expense(let expense, let payer, let shares) = proposal.item else {
            Issue.record("expected an expense, got \(model.state)")
            return
        }
        #expect(payer.id == fixture.priya.id)
        #expect(expense.split.participants == [fixture.priya.id, fixture.me.id])
        #expect(shares.map(\.person.id) == [fixture.me.id, fixture.priya.id])
    }

    @Test func refusesAReplyFromAnotherPhone() throws {
        let (fixture, store, _) = try setUp()
        let packed = try fragment(BalanceReplyFormatTests.expense(), token: BalanceReplyStore.makeToken())
        let model = ReplyReviewModel(fragment: packed, services: fixture.services, store: store)
        #expect(model.state == .problem(.otherPhone(groupName: "Flat")))
        #expect(model.add() == nil)
    }

    @Test func refusesSomeoneTheLinkNeverNumbered() throws {
        let (fixture, store, token) = try setUp()
        let packed = try fragment(BalanceReplyFormatTests.expense(participants: [0, 7]), token: token)
        let model = ReplyReviewModel(fragment: packed, services: fixture.services, store: store)
        #expect(model.state == .problem(.unknownPerson))
    }

    @Test func refusesSomeoneWhoLeft() throws {
        let (fixture, store, token) = try setUp()
        try fixture.services.groups.removeMember(fixture.priya.id, from: fixture.group.id)
        let packed = try fragment(BalanceReplyFormatTests.expense(), token: token)
        let model = ReplyReviewModel(fragment: packed, services: fixture.services, store: store)
        #expect(model.state == .problem(.personLeft(name: "Priya", groupName: "Flat")))
    }

    @Test func saysWhenALinkIsBroken() throws {
        let (fixture, store, _) = try setUp()
        let model = ReplyReviewModel(fragment: "AAAA", services: fixture.services, store: store)
        #expect(model.state == .problem(.unreadable))
    }
}

@MainActor
@Suite("Reply links")
struct ReplyLinkRoutingTests {
    @Test func opensTheReviewSheet() throws {
        let url = try #require(URL(string: "splt://reply?d=AbC-_123"))
        #expect(DeepLink(url: url) == .reply("AbC-_123"))
        #expect(DeepLink(url: DeepLink.reply("AbC-_123").url) == .reply("AbC-_123"))
        #expect(DeepLink(url: try #require(URL(string: "splt://reply"))) == nil)
        #expect(DeepLink(url: try #require(URL(string: "splt://reply?d="))) == nil)

        let router = Router()
        #expect(router.open(url))
        #expect(router.sheet == .reviewReply)
        #expect(router.pendingReply == "AbC-_123")

        router.open(.reply("second"))
        #expect(router.pendingReply == "second")

        router.sheet = nil
        #expect(router.pendingReply == nil)
    }
}
