import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Invites made for one person")
struct JoinInviteTests {
    private let shareURL = URL(string: "https://www.icloud.com/share/0AbCdEfGhIjKlMnOp")!

    /// The flat, with Hana added by name and owing Sam. The person joining is new, so they are in
    /// no expense yet, as on a device that just joined.
    private func scene() throws -> (fixture: Fixture, hana: Person) {
        let fixture = try Fixture()
        let hana = Person(name: "Hana Sato", kind: .placeholder)
        try fixture.services.people.add(hana)
        try fixture.services.groups.addMember(hana.id, to: fixture.group.id)
        try fixture.services.expenses.add(fixture.expense("Groceries", cents: 4000, paidBy: fixture.sam, splitBetween: [fixture.sam.id, hana.id]))
        return (fixture, hana)
    }

    private func snapshot(_ fixture: Fixture, inviting person: PersonID) throws -> BalanceSnapshot {
        let group = try #require(try fixture.services.groups.group(id: fixture.group.id))
        let people = try fixture.services.people.people(ids: group.memberIDs)
        return BalanceSnapshot(
            group: group, me: fixture.me.id,
            people: Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) }),
            expenses: try fixture.services.expenses.expenses(in: group.id),
            balances: try fixture.services.groups.balances(for: group.id),
            includesExpenses: true, now: fixture.clock.start, invite: (shareURL, person)
        )
    }

    // MARK: The link

    @Test func theLinkCarriesTheInviteAndWhoItIsFor() throws {
        let (fixture, hana) = try scene()
        let made = try snapshot(fixture, inviting: hana.id)
        let join = try #require(made.join)
        #expect(made.members[join.person].name == "Hana Sato")
        #expect(join.personID == hana.id.rawValue)
        #expect(join.shareURL == shareURL)

        let link = try BalanceLink.url(for: made)
        let read = try BalanceLink.snapshot(fromFragment: try #require(link.fragment))
        #expect(read == made)
    }

    @Test func aBalanceLinkStaysWithoutAnInvite() throws {
        let (fixture, _) = try scene()
        let group = try #require(try fixture.services.groups.group(id: fixture.group.id))
        let plain = BalanceSnapshot(
            group: group, me: fixture.me.id, people: [:], expenses: [], balances: nil,
            includesExpenses: false, now: fixture.clock.start
        )
        #expect(plain.join == nil)
        #expect(!(try BalanceLink.fragment(for: plain)).isEmpty)
        let link = try BalanceLink.url(for: plain)
        #expect(JoinInvite(url: link) == nil)
    }

    @Test func refusesAnInviteThatIsNotICloud() throws {
        let (fixture, hana) = try scene()
        var made = try snapshot(fixture, inviting: hana.id)
        made.join?.shareURL = URL(string: "https://evil.example/share/x")!
        #expect(throws: BalanceSnapshot.FormatError.invalid("join")) { try made.validate() }
        made.join?.shareURL = URL(string: "https://icloud.com.evil.example/x")!
        #expect(throws: BalanceSnapshot.FormatError.invalid("join")) { try made.validate() }
        made.join?.shareURL = shareURL
        made.join?.person = 99
        #expect(throws: BalanceSnapshot.FormatError.invalid("join")) { try made.validate() }
    }

    // MARK: Reading invites

    @Test func readsTheAppLinkAndThePageLink() throws {
        let (fixture, hana) = try scene()
        let expected = JoinInvite(shareURL: shareURL, personID: hana.id)

        #expect(JoinInvite(url: expected.url) == expected)
        #expect(DeepLink(url: expected.url) == .join(expected))
        #expect(DeepLink.join(expected).url == expected.url)

        let page = try BalanceLink.url(for: try snapshot(fixture, inviting: hana.id))
        #expect(JoinInvite(url: page) == expected)
    }

    @Test func findsTheInviteInAPastedMessage() throws {
        let (fixture, hana) = try scene()
        let page = try BalanceLink.url(for: try snapshot(fixture, inviting: hana.id))
        let message = "Hi Hana, I've added you to Flat on Splt. Join to see what you owe and add expenses too.\n\(page.absoluteString)"
        #expect(JoinInvite(text: message) == JoinInvite(shareURL: shareURL, personID: hana.id))
        #expect(JoinInvite(text: "  \(page.absoluteString)  ") != nil)
        #expect(JoinInvite(text: "See you at dinner") == nil)
        #expect(JoinInvite(text: "https://example.com/Splt/b/#abc") == nil)
    }

    @Test func refusesAppLinksThatAreNotInvites() {
        let id = UUID().uuidString
        #expect(JoinInvite(url: URL(string: "splt://join?as=\(id)")!) == nil)
        #expect(JoinInvite(url: URL(string: "splt://join?share=https%3A%2F%2Fevil.example%2Fx&as=\(id)")!) == nil)
        #expect(JoinInvite(url: URL(string: "splt://join?share=https%3A%2F%2Fwww.icloud.com%2Fshare%2Fx&as=nope")!) == nil)
    }

    @Test func theRouterHandsTheInviteToSync() {
        let router = Router()
        router.present(.addExpense)
        let invite = JoinInvite(shareURL: shareURL, personID: PersonID())
        #expect(router.open(invite.url))
        #expect(router.pendingJoin == invite)
        #expect(router.sheet == nil)
    }

    // MARK: Joining as the person

    @Test func joiningTakesOverThePersonAddedByName() throws {
        let (fixture, hana) = try scene()
        let model = JoinGroupModel(claim: JoinClaim(group: fixture.group.id, person: hana.id), services: fixture.services)
        #expect(model.invited == hana)
        #expect(model.others.isEmpty)
        #expect(model.invitedLine == "You owe Sam \(usdAmount(2000).formatted())")

        model.join(as: hana)

        #expect(model.didJoin)
        #expect(model.errorMessage == nil)
        #expect(try fixture.services.people.person(id: hana.id) == nil)
        let members = try #require(try fixture.services.groups.group(id: fixture.group.id)).memberIDs
        #expect(!members.contains(hana.id))
        #expect(members.contains(fixture.me.id))
    }

    @Test func listsTheOthersStillWaiting() throws {
        let (fixture, hana) = try scene()
        let ken = Person(name: "Ken", kind: .placeholder)
        try fixture.services.people.add(ken)
        try fixture.services.groups.addMember(ken.id, to: fixture.group.id)
        let model = JoinGroupModel(claim: JoinClaim(group: fixture.group.id, person: hana.id), services: fixture.services)
        #expect(model.others == [ken])
        #expect(!model.isEmpty)
    }

    @Test func nothingToAskOnceThePersonWasClaimed() throws {
        let (fixture, _) = try scene()
        let model = JoinGroupModel(claim: JoinClaim(group: fixture.group.id, person: PersonID()), services: fixture.services)
        #expect(model.invited == nil)
        #expect(model.others.map(\.name) == ["Hana Sato"])
        let settled = try Fixture()
        let empty = JoinGroupModel(claim: JoinClaim(group: settled.group.id, person: PersonID()), services: settled.services)
        #expect(empty.isEmpty)
    }

    @Test func describesTheBalanceInOneLine() {
        let hana = PersonID(), maya = PersonID(), jonas = PersonID()
        let names = [maya: "Maya", jonas: "Jonas"]
        let owe = Debt(debtor: hana, creditor: maya, amount: usdAmount(15623))
        #expect(JoinGroupModel.line(for: hana, debts: [owe], names: names) == "You owe Maya \(usdAmount(15623).formatted())")
        let owed = Debt(debtor: jonas, creditor: hana, amount: usdAmount(500))
        #expect(JoinGroupModel.line(for: hana, debts: [owed], names: names) == "Jonas owes you \(usdAmount(500).formatted())")
        #expect(JoinGroupModel.line(for: hana, debts: [], names: names) == "Settled up")
        let twice = [owe, Debt(debtor: hana, creditor: jonas, amount: usdAmount(100))]
        #expect(JoinGroupModel.line(for: hana, debts: twice, names: names) == "You owe 2 people")
    }

    // MARK: Sync

    @Test func anInviteLinkWithoutICloudFailsCalmly() async throws {
        let runtime = SyncRuntime()
        var failures: [String] = []
        runtime.onInvitationFailed = { failures.append($0) }
        await runtime.start(services: try DataServices.inMemory())
        runtime.receive(ShareInvitation(shareURL: shareURL, claim: PersonID()))
        #expect(await eventually { failures == ["iCloud sync is not available in this build."] })
        #expect(runtime.takeClaim(for: GroupID()) == nil)
    }

    @Test func aClaimIsTakenOnce() {
        let runtime = SyncRuntime(liveServices: { nil })
        let group = GroupID(), person = PersonID()
        runtime.noteClaim(person, in: group)
        #expect(runtime.takeClaim(for: group) == person)
        #expect(runtime.takeClaim(for: group) == nil)
    }
}
