import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Orbit board")
struct OrbitBoardTests {
    private let me = Person(name: "Jamie Rivera", kind: .me)
    private let sam = Person(name: "Sam Lee")
    private let priya = Person(name: "Priya Nair")
    private let english = GroupsTestCalendar.english

    private func board(
        members: [Person]? = nil, me meID: PersonID? = nil, nets: [PersonID: Int64] = [:], debts: [Debt] = []
    ) -> OrbitBoard {
        OrbitBoard(
            members: members ?? [sam, priya, me],
            me: meID ?? me.id,
            nets: nets.mapValues(usdAmount),
            debts: debts,
            currencyCode: "USD"
        )
    }

    private func debt(_ from: Person, _ to: Person, _ cents: Int64) -> Debt {
        Debt(debtor: from.id, creditor: to.id, amount: usdAmount(cents))
    }

    @Test func youSitFirst() {
        #expect(board().nodes.map(\.name) == ["Jamie Rivera", "Sam Lee", "Priya Nair"])
        #expect(board().nodes.first?.isMe == true)
        #expect(board().nodes.map(\.firstName) == ["Jamie", "Sam", "Priya"])
    }

    @Test func peopleWhoLeftStillGetAPlaceWhenTheyAreInADebt() {
        let ghost = Person(name: "Gone")
        let board = board(debts: [Debt(debtor: ghost.id, creditor: me.id, amount: usdAmount(500))])
        #expect(board.nodes.count == 4)
        #expect(board.name(of: ghost.id) == "Someone")
    }

    @Test func theCenterShowsYourBalance() {
        let owed = board(nets: [me.id: 2000, sam.id: -2000])
        #expect(owed.center(for: .none) == OrbitCenter(kind: .owed, subject: "You", subjectIsMe: true, amount: usdAmount(2000)))
        let owing = board(nets: [me.id: -750])
        #expect(owing.center(for: .none).kind == .owes)
        #expect(owing.center(for: .none).amount == usdAmount(750))
    }

    @Test func theCenterFollowsTheFocus() {
        let board = board(nets: [me.id: 2000, sam.id: -1500, priya.id: -500])
        let center = board.center(for: .person(sam.id))
        #expect(center.kind == .owes)
        #expect(center.subject == "Sam")
        #expect(!center.subjectIsMe)
        #expect(center.amount == usdAmount(1500))
    }

    @Test func aSquareGroupIsSettled() {
        let board = board()
        #expect(board.isSettled)
        #expect(board.center(for: .none).kind == .settled)
        #expect(board.center(for: .none).amount.isZero)
        #expect(board.summary(locale: english) == "Everyone is settled up")
    }

    @Test func withoutAProfileTheCenterShowsWhatIsLeftToPay() {
        let board = OrbitBoard(
            members: [sam, priya], me: nil, nets: [:],
            debts: [debt(sam, priya, 1200), debt(priya, sam, 300)], currencyCode: "USD"
        )
        let center = board.center(for: .none)
        #expect(center.kind == .toSettle)
        #expect(center.amount == usdAmount(1500))
    }

    @Test func onlyThePickedCurrencyIsOnTheRing() {
        let yen = Money(minorUnits: 500, currencyCode: "JPY")
        let board = board(debts: [debt(sam, me, 400), Debt(debtor: sam.id, creditor: priya.id, amount: yen)])
        #expect(board.transfers.count == 1)
        #expect(board.transfers.first?.amount == usdAmount(400))
    }

    @Test func sentencesReadFromYourSide() {
        let board = board(debts: [debt(sam, me, 1000), debt(me, priya, 500), debt(sam, priya, 200)])
        let sentences = board.transfers.map { board.sentence(for: $0) }
        #expect(sentences == ["Sam Lee owes you", "You owe Priya Nair", "Sam Lee owes Priya Nair"])
        #expect(board.spoken(board.transfers[0], locale: english) == "Sam Lee owes you $10.00")
    }

    @Test func theSummaryCountsPayments() {
        let board = board(debts: [debt(sam, me, 1000), debt(priya, me, 500)])
        #expect(board.summary(locale: english) == "2 payments would settle this group.")
        let one = self.board(debts: [debt(sam, me, 1000)])
        #expect(one.summary(locale: english) == "1 payment would settle this group.")
    }

    @Test func transfersKeepTheirOrderAndIds() {
        let board = board(debts: [debt(sam, me, 1000), debt(priya, me, 500)])
        #expect(board.transfers.map(\.id) == ["\(sam.id)>\(me.id)", "\(priya.id)>\(me.id)"])
        #expect(board.transfers[0].debt == debt(sam, me, 1000))
    }
}
