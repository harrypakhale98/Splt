import Foundation
import Testing
@testable import Splt

@MainActor
@Suite("Friend invites and links")
struct FriendInviteTests {
    private let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test func linkRoundTrips() throws {
        let invite = FriendInvite(name: "Maya Chen", personID: id)
        let parsed = try #require(FriendInvite(url: invite.url))
        #expect(parsed == invite)
        #expect(invite.url.scheme == "splt")
        #expect(invite.url.host() == "invite")
    }

    @Test func namesWithSpacesAndSymbolsSurvive() throws {
        let invite = FriendInvite(name: "  Zoe  O'Brien & Co ", personID: nil)
        #expect(invite.name == "Zoe O'Brien & Co")
        let parsed = try #require(FriendInvite(url: invite.url))
        #expect(parsed.name == "Zoe O'Brien & Co")
        #expect(parsed.personID == nil)
    }

    @Test func rejectsLinksWithoutAName() {
        #expect(FriendInvite(url: URL(string: "splt://invite")!) == nil)
        #expect(FriendInvite(url: URL(string: "splt://invite?name=%20")!) == nil)
        #expect(FriendInvite(url: URL(string: "https://invite?name=Sam")!) == nil)
        #expect(FriendInvite(url: URL(string: "splt://group?name=Sam")!) == nil)
    }

    @Test func ignoresAnIdThatIsNotAUUID() throws {
        let invite = try #require(FriendInvite(url: URL(string: "splt://invite?name=Sam&id=nope")!))
        #expect(invite.personID == nil)
    }

    @Test func shareMessageContainsTheLink() {
        let invite = FriendInvite(name: "Sam", personID: id)
        #expect(invite.shareMessage.contains(invite.url.absoluteString))
    }

    @Test func deepLinkParsesInviteAndSettle() throws {
        let invite = FriendInvite(name: "Sam", personID: id)
        #expect(DeepLink(url: invite.url) == .invite(invite))
        #expect(DeepLink.invite(invite).url == invite.url)
        let settle = URL(string: "splt://settle/\(id.uuidString)")!
        #expect(DeepLink(url: settle) == .settle(id))
        #expect(DeepLink.settle(id).url == settle)
        #expect(DeepLink(url: URL(string: "splt://settle/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "splt://invite/extra?name=Sam")!) == nil)
    }

    @Test func routerHoldsAnInviteForTheSheet() {
        let router = Router()
        let invite = FriendInvite(name: "Sam", personID: id)
        #expect(router.open(invite.url))
        #expect(router.pendingInvite == invite)
        #expect(router.sheet == .newFriend)
    }

    @Test func routerOpensSettleOnTheFriendsTab() {
        let router = Router()
        router.open(.settle(id))
        #expect(router.selectedTab == .friends)
        #expect(router.friendsPath == [.friend(id)])
        #expect(router.pendingSettleFriend == id)
    }

    @Test func scanningReadsOnlySpltInvites() {
        let invite = FriendInvite(name: "Sam", personID: id)
        #expect(QRInviteScan.invite(from: invite.url.absoluteString) == invite)
        #expect(QRInviteScan.invite(from: "  \(invite.url.absoluteString)\n") == invite)
        #expect(QRInviteScan.invite(from: "https://example.com") == nil)
        #expect(QRInviteScan.invite(from: "splt://add-expense") == nil)
        #expect(QRInviteScan.invite(from: "hello") == nil)
    }
}
