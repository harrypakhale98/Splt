import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("To Split widget count")
struct ToSplitSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func payment(daysAgo: Double) -> PendingPayment {
        PendingPayment(
            id: UUID(), merchant: "Nobu", amount: Money(minorUnits: 4_200, currencyCode: "USD"),
            date: now.addingTimeInterval(-daysAgo * day), source: .wallet
        )
    }

    @Test func countsWhatTheAppCountedAndSkipsTheRest() {
        let counted = payment(daysAgo: 1)
        let quiet = payment(daysAgo: 1)
        let snapshot = ToSplitSnapshot(reviewed: [counted.id, quiet.id], counted: [counted.id])
        #expect(snapshot.count(in: [counted, quiet], at: now) == 1)
    }

    @Test func aSharedPaymentTheAppHasNotSeenCounts() {
        let seen = payment(daysAgo: 1)
        let shared = payment(daysAgo: 0)
        let snapshot = ToSplitSnapshot(reviewed: [seen.id], counted: [seen.id])
        #expect(snapshot.count(in: [seen, shared], at: now) == 2)
    }

    @Test func nothingSavedYetCountsEveryRecentPayment() {
        let recent = payment(daysAgo: 2)
        let old = payment(daysAgo: 8)
        #expect(ToSplitSnapshot().count(in: [recent, old], at: now) == 1)
    }

    @Test func countDropsWhenAPaymentTurnsAWeekOld() {
        let older = payment(daysAgo: 6)
        let newer = payment(daysAgo: 2)
        let snapshot = ToSplitSnapshot(reviewed: [older.id, newer.id], counted: [older.id, newer.id])
        let drops = snapshot.changes(in: [older, newer], after: now)
        #expect(drops.count == 2)
        #expect(drops[0] < drops[1])
        #expect(snapshot.count(in: [older, newer], at: drops[0].addingTimeInterval(-2)) == 2)
        #expect(snapshot.count(in: [older, newer], at: drops[0]) == 1)
        #expect(snapshot.count(in: [older, newer], at: drops[1]) == 0)
    }

    @Test func aWrapUpKeepsOnlyWhatStillWaitsAndEndsOnTime() {
        let left = payment(daysAgo: 9)
        let resolved = UUID()
        let until = now.addingTimeInterval(3 * day)
        let wrapUp = ToSplitSnapshot.WrapUp(groupID: UUID(), tripName: "Lisbon", paymentIDs: [left.id, resolved], offeredUntil: until)
        let snapshot = ToSplitSnapshot(reviewed: [left.id], wrapUps: [wrapUp])
        #expect(snapshot.wrapUps(in: [left], at: now).first?.paymentIDs == [left.id])
        #expect(snapshot.wrapUps(in: [left], at: until).isEmpty)
        #expect(snapshot.wrapUps(in: [], at: now).isEmpty)
        #expect(snapshot.changes(in: [left], after: now) == [until])
    }

    @Test func toSplitIsNewestFirst() {
        let older = payment(daysAgo: 3)
        let newer = payment(daysAgo: 1)
        #expect(ToSplitSnapshot().toSplit(in: [older, newer], at: now).map(\.id) == [newer.id, older.id])
    }

    @Test func readsOneSavedByTheLastBuild() throws {
        let id = UUID()
        let old = Data(#"{"reviewed":["\#(id.uuidString)"],"counted":["\#(id.uuidString)"]}"#.utf8)
        let snapshot = try JSONDecoder().decode(ToSplitSnapshot.self, from: old)
        #expect(snapshot.counted == [id])
        #expect(snapshot.wrapUps.isEmpty)
        #expect(!snapshot.hidesDetails)
    }

    @Test func survivesAWriteAndRead() throws {
        let defaults = try #require(UserDefaults(suiteName: "ToSplitSnapshotTests"))
        defaults.removePersistentDomain(forName: "ToSplitSnapshotTests")
        let snapshot = ToSplitSnapshot(reviewed: [UUID(), UUID()], counted: [UUID()], hidesDetails: true)
        snapshot.save(to: defaults)
        #expect(ToSplitSnapshot.load(from: defaults) == snapshot)
    }
}
