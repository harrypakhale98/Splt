import Foundation

/// What the app last decided about the waiting payments, kept where the widgets can read it.
/// The widget works the count out from the inbox file itself, so it stays right when the share
/// extension adds a payment or a payment turns a week old while the app is closed.
struct ToSplitSnapshot: Codable, Hashable, Sendable {
    /// A trip that ended lately with payments from it still waiting, as the app offers it in To Split.
    struct WrapUp: Codable, Hashable, Sendable {
        var groupID: UUID
        var tripName: String
        var paymentIDs: [UUID]
        /// Two weeks after the trip ends, when the app stops offering it.
        var offeredUntil: Date
    }

    /// A payment older than this is kept but no longer asked about.
    static let staleAfter: TimeInterval = 7 * 86_400
    static let key = "inbox.toSplit"

    /// Every payment the app looked at.
    var reviewed: Set<UUID> = []
    /// The ones it decided are worth asking about.
    var counted: Set<UUID> = []
    var wrapUps: [WrapUp] = []
    /// The Face ID lock is on, so widgets show how many payments wait but never what they were.
    var hidesDetails = false

    init(reviewed: Set<UUID> = [], counted: Set<UUID> = [], wrapUps: [WrapUp] = [], hidesDetails: Bool = false) {
        self.reviewed = reviewed
        self.counted = counted
        self.wrapUps = wrapUps
        self.hidesDetails = hidesDetails
    }

    /// Reads one saved by an older build, which had only the first two.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reviewed = try container.decodeIfPresent(Set<UUID>.self, forKey: .reviewed) ?? []
        counted = try container.decodeIfPresent(Set<UUID>.self, forKey: .counted) ?? []
        wrapUps = try container.decodeIfPresent([WrapUp].self, forKey: .wrapUps) ?? []
        hidesDetails = try container.decodeIfPresent(Bool.self, forKey: .hidesDetails) ?? false
    }

    /// Whether a payment counts at `now`. One the app hasn't looked at yet counts until it is a week old.
    func counts(_ payment: PendingPayment, at now: Date) -> Bool {
        guard now.timeIntervalSince(payment.date) <= Self.staleAfter else { return false }
        return !reviewed.contains(payment.id) || counted.contains(payment.id)
    }

    func count(in pending: [PendingPayment], at now: Date) -> Int {
        pending.filter { counts($0, at: now) }.count
    }

    /// The payments to ask about at `now`, newest first.
    func toSplit(in pending: [PendingPayment], at now: Date) -> [PendingPayment] {
        pending.filter { counts($0, at: now) }.sorted { $0.date > $1.date }
    }

    /// The wrap-ups still on offer at `now`, each with only the payments from it that still wait.
    func wrapUps(in pending: [PendingPayment], at now: Date) -> [WrapUp] {
        let waiting = Set(pending.map(\.id))
        return wrapUps.compactMap { wrapUp in
            guard now < wrapUp.offeredUntil else { return nil }
            var left = wrapUp
            left.paymentIDs = wrapUp.paymentIDs.filter(waiting.contains)
            return left.paymentIDs.isEmpty ? nil : left
        }
    }

    /// The moments after `now` when what the widgets show changes: a counted payment turns a week old,
    /// or a wrap-up stops being offered. Earliest first.
    func changes(in pending: [PendingPayment], after now: Date) -> [Date] {
        let drops = pending.filter { counts($0, at: now) }.map { $0.date.addingTimeInterval(Self.staleAfter + 1) }
        let endings = wrapUps(in: pending, at: now).map(\.offeredUntil)
        return Set(drops + endings).filter { $0 > now }.sorted()
    }

    static func load(from defaults: UserDefaults) -> ToSplitSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(ToSplitSnapshot.self, from: data) else { return ToSplitSnapshot() }
        return snapshot
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
