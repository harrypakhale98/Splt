import SpltCore
import Testing
@testable import Splt

@Suite("Friend visibility")
struct FriendVisibilityStoreTests {
    @Test func remembersHiddenAndBlockedPeople() {
        let store = FriendVisibilityStore(defaults: isolatedDefaults())
        let ana = PersonID(), ben = PersonID(), cy = PersonID()
        store.set(.hidden, for: ana)
        store.set(.blocked, for: ben)
        #expect(store.state(of: ana) == .hidden)
        #expect(store.state(of: ben) == .blocked)
        #expect(store.state(of: cy) == nil)
        #expect(store.ids(in: .hidden) == [ana])
        #expect(store.ids(in: .blocked) == [ben])
        #expect(store.hiddenOrBlocked == [ana, ben])
    }

    @Test func clearingBringsAPersonBack() {
        let store = FriendVisibilityStore(defaults: isolatedDefaults())
        let ana = PersonID()
        store.set(.blocked, for: ana)
        store.set(nil, for: ana)
        #expect(store.state(of: ana) == nil)
        #expect(store.hiddenOrBlocked.isEmpty)
    }

    @Test func changingStateReplacesTheOldOne() {
        let store = FriendVisibilityStore(defaults: isolatedDefaults())
        let ana = PersonID()
        store.set(.hidden, for: ana)
        store.set(.blocked, for: ana)
        #expect(store.ids(in: .hidden).isEmpty)
        #expect(store.state(of: ana) == .blocked)
    }

    @Test func stateSurvivesANewStoreOnTheSameDefaults() {
        let defaults = isolatedDefaults()
        let ana = PersonID()
        FriendVisibilityStore(defaults: defaults).set(.hidden, for: ana)
        #expect(FriendVisibilityStore(defaults: defaults).state(of: ana) == .hidden)
    }
}
