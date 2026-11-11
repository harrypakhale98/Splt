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
        let expected = JoinInvite(shareURL: shareURL, personID: hana.id, name: "Hana Sato")

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
        #expect(JoinInvite(text: message) == JoinInvite(shareURL: shareURL, personID: hana.id, name: "Hana Sato"))
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
        let invite = JoinInvite(shareURL: shareURL, personID: PersonID(), name: "Hana")
        #expect(router.open(invite.url))
        #expect(router.pendingJoin == invite)
        #expect(router.sheet == nil)
    }

    // MARK: Joining as the person

    @Test func joiningTakesOverThePersonAddedByName() throws {
        let (fixture, hana) = try scene()
        let profile = AccountProfile(defaults: freshDefaults(), deviceName: "iPhone")
        let model = JoinGroupModel(
            claim: JoinClaim(group: fixture.group.id, person: hana.id), services: fixture.services, profile: profile
        )
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
        // the fixture's profile was never named on this device, so it takes the name the group knows
        #expect(profile.displayName == "Hana Sato")
        #expect(try fixture.services.people.me()?.name == "Hana Sato")
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

    // MARK: One link for the group chat

    private func groupSnapshot(_ fixture: Fixture, waiting: [PersonID]) throws -> BalanceSnapshot {
        let group = try #require(try fixture.services.groups.group(id: fixture.group.id))
        let people = try fixture.services.people.people(ids: group.memberIDs)
        return BalanceSnapshot(
            group: group, me: fixture.me.id,
            people: Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) }),
            expenses: [], balances: nil, includesExpenses: false, now: fixture.clock.start,
            inviteEveryone: (shareURL, waiting)
        )
    }

    @Test func oneLinkCarriesEveryoneStillWaiting() throws {
        let (fixture, hana) = try scene()
        let ken = Person(name: "Ken", kind: .placeholder)
        try fixture.services.people.add(ken)
        try fixture.services.groups.addMember(ken.id, to: fixture.group.id)
        let made = try groupSnapshot(fixture, waiting: [hana.id, ken.id])
        let group = try #require(made.groupJoin)
        #expect(group.seats.map { made.members[$0.person].name } == ["Hana Sato", "Ken"])
        #expect(made.join == nil)

        let link = try BalanceLink.url(for: made)
        #expect(try BalanceLink.snapshot(fromFragment: try #require(link.fragment)) == made)
        // pasted, it joins and then asks who you are
        let invite = try #require(JoinInvite(url: link))
        #expect(invite.personID == nil)
        #expect(invite.name == nil)
        #expect(invite.joinAs == .askWho)
        #expect(JoinInvite(url: invite.url) == invite)
    }

    @Test func refusesAGroupLinkWithNobodyWaiting() throws {
        let (fixture, _) = try scene()
        #expect(try groupSnapshot(fixture, waiting: []).groupJoin == nil)
        var made = try groupSnapshot(fixture, waiting: [fixture.sam.id])
        made.groupJoin?.seats = []
        #expect(throws: BalanceSnapshot.FormatError.invalid("join")) { try made.validate() }
    }

    @Test func aGroupLinkAsksWhoYouAre() throws {
        let (fixture, hana) = try scene()
        let model = JoinGroupModel(claim: JoinClaim(group: fixture.group.id, person: nil), services: fixture.services)
        #expect(model.invited == nil)
        #expect(model.others == [hana])
    }

    // MARK: Names

    private func freshDefaults() -> UserDefaults {
        let name = "join-invite-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func someoneWithoutANameTakesTheInvitedOne() throws {
        let services = try DataServices.inMemory()
        let profile = AccountProfile(defaults: freshDefaults(), deviceName: "Hana's iPhone")
        // a name only suggested from the device doesn't count as chosen
        #expect(profile.hasName)
        #expect(!profile.hasChosenName)
        try profile.takeInvitedName("Hana Sato", people: services.people)
        #expect(profile.displayName == "Hana Sato")
        #expect(profile.hasChosenName)
        #expect(try services.people.me()?.name == "Hana Sato")
    }

    @Test func aChosenNameStays() throws {
        let services = try DataServices.inMemory()
        let profile = AccountProfile(defaults: freshDefaults(), deviceName: "iPhone")
        profile.displayName = "Hana"
        profile.save()
        try profile.takeInvitedName("Hana Sato", people: services.people)
        #expect(profile.displayName == "Hana")
    }

    @Test func theAppLinkCarriesTheName() {
        let id = PersonID()
        let invite = JoinInvite(shareURL: shareURL, personID: id, name: "  Hana Sato \n")
        #expect(invite.name == "Hana Sato")
        #expect(JoinInvite(url: invite.url)?.name == "Hana Sato")
        // a name without a person means nothing, so a group link carries none
        #expect(JoinInvite(shareURL: shareURL, personID: nil, name: "Hana").url.query()?.contains("name") == false)
    }

    // MARK: The Invite sheet

    private struct ICloudSharing: GroupSharing {
        let url: URL
        func inviteURL(for groupID: GroupID, groupName: String) async throws -> URL { url }
        func isInviteOnly(groupID: GroupID) async throws -> Bool { false }
        func leave(groupID: GroupID) async throws {}
        func isSharedByMe(groupID: GroupID) async -> Bool { true }
        func groupsSharedWithMe() async -> Set<GroupID> { [] }
    }

    @Test func theInviteSheetMakesASendLinkAndAShorterScanLink() async throws {
        let (fixture, hana) = try scene()
        let model = InvitePersonModel(groupID: fixture.group.id, invitee: .person(hana), services: fixture.services)
        await model.load(using: ICloudSharing(url: shareURL))
        guard case .ready(let links) = model.state else {
            Issue.record("not ready: \(model.state)")
            return
        }
        #expect(links.scan.absoluteString.count < links.send.absoluteString.count)
        #expect(JoinInvite(url: links.send)?.personID == hana.id)
        #expect(JoinInvite(url: links.scan)?.personID == hana.id)
        #expect(model.title == "Invite Hana")
        #expect(model.text(with: links.send).hasSuffix(links.send.absoluteString))
    }

    @Test func inviteEveryoneListsWhoIsWaiting() async throws {
        let (fixture, hana) = try scene()
        let model = InvitePersonModel(groupID: fixture.group.id, invitee: .everyone, services: fixture.services)
        #expect(model.waiting == [hana])
        #expect(model.title == "Invite Everyone")
        await model.load(using: ICloudSharing(url: shareURL))
        guard case .ready(let links) = model.state else {
            Issue.record("not ready: \(model.state)")
            return
        }
        let invite = try #require(JoinInvite(url: links.send))
        #expect(invite.personID == nil)
    }

    @Test func withoutICloudThereIsNothingToSend() async throws {
        let (fixture, hana) = try scene()
        let model = InvitePersonModel(groupID: fixture.group.id, invitee: .person(hana), services: fixture.services)
        await model.load(using: LocalGroupSharing())
        #expect(model.state == .needsICloud)
    }

    @Test func sendsStraightToTheNumberOrAddressTheyWereAddedWith() {
        #expect(InvitePersonModel.Recipient(contactHint: "+44 7700 900123") == .phone("+44 7700 900123"))
        #expect(InvitePersonModel.Recipient(contactHint: " hana@example.com ") == .email("hana@example.com"))
        #expect(InvitePersonModel.Recipient(contactHint: "Hana") == nil)
        #expect(InvitePersonModel.Recipient(contactHint: nil) == nil)
    }

    // MARK: Sync

    @Test func anInviteLinkWithoutICloudFailsCalmly() async throws {
        let runtime = SyncRuntime()
        var failures: [String] = []
        runtime.onInvitationFailed = { failures.append($0) }
        await runtime.start(services: try DataServices.inMemory())
        runtime.receive(ShareInvitation(shareURL: shareURL, claim: .person(PersonID())))
        #expect(await eventually { failures == ["iCloud sync is not available in this build."] })
        #expect(runtime.takeClaim(for: GroupID()) == nil)
    }

    @Test func aClaimIsTakenOnce() {
        let runtime = SyncRuntime(liveServices: { nil })
        let group = GroupID(), person = PersonID()
        runtime.noteClaim(.person(person), in: group)
        #expect(runtime.takeClaim(for: group) == .person(person))
        #expect(runtime.takeClaim(for: group) == nil)
    }
}
