import Foundation
import SpltCore

/// A payment caught from Wallet, a bank text or a screenshot, waiting for you to split it or keep it.
/// It stays on this iPhone and never syncs. Only the expense made from it does.
struct PendingPayment: Codable, Hashable, Sendable, Identifiable {
    enum Source: String, Codable, Sendable {
        case wallet
        case text
        case screenshot
    }

    enum Status: String, Codable, Sendable {
        case pending
        /// You said it was yours alone.
        case dismissed
        case split
    }

    var id: UUID
    var merchant: String
    var amount: Money
    var date: Date
    var source: Source
    var status: Status = .pending
    var resolvedAt: Date?
    /// The expense made from it, once split.
    var expenseID: UUID?

    var merchantKey: String { MerchantKey.make(merchant) }
}

extension PendingPayment {
    /// Fields with a default may be missing, so a file from an older or newer build still reads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        merchant = try container.decode(String.self, forKey: .merchant)
        amount = try container.decode(Money.self, forKey: .amount)
        date = try container.decode(Date.self, forKey: .date)
        source = (try? container.decode(Source.self, forKey: .source)) ?? .wallet
        status = (try? container.decode(Status.self, forKey: .status)) ?? .pending
        resolvedAt = try? container.decodeIfPresent(Date.self, forKey: .resolvedAt)
        expenseID = try? container.decodeIfPresent(UUID.self, forKey: .expenseID)
    }
}

/// What Splt remembers about a merchant, by `MerchantKey`: where you split it last and whether to stay quiet about it.
struct MerchantMemory: Codable, Hashable, Sendable {
    var groupID: UUID?
    var category: ExpenseCategory?
    var splitCount = 0
    var dismissCount = 0
    var isMuted = false
}

extension MerchantMemory {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupID = try? container.decodeIfPresent(UUID.self, forKey: .groupID)
        category = try? container.decodeIfPresent(ExpenseCategory.self, forKey: .category)
        splitCount = (try? container.decodeIfPresent(Int.self, forKey: .splitCount)) ?? 0
        dismissCount = (try? container.decodeIfPresent(Int.self, forKey: .dismissCount)) ?? 0
        isMuted = (try? container.decodeIfPresent(Bool.self, forKey: .isMuted)) ?? false
    }
}

/// Everything in the inbox file.
struct PaymentInboxState: Codable, Hashable, Sendable {
    var payments: [PendingPayment] = []
    var merchants: [String: MerchantMemory] = [:]
    /// When the last payment came in from Wallet, so setup can say it works.
    var lastWalletCaptureAt: Date?

    init() {}

    /// Reads what it can: one payment or merchant that won't decode is left out, not the whole inbox.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rows = (try? container.decodeIfPresent([Lossy<PendingPayment>].self, forKey: .payments)) ?? []
        payments = rows.compactMap(\.value)
        let memories = (try? container.decodeIfPresent([String: Lossy<MerchantMemory>].self, forKey: .merchants)) ?? [:]
        merchants = memories.compactMapValues(\.value)
        lastWalletCaptureAt = try? container.decodeIfPresent(Date.self, forKey: .lastWalletCaptureAt)
    }

    private enum CodingKeys: String, CodingKey {
        case payments, merchants, lastWalletCaptureAt
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    static let duplicateWindow: TimeInterval = 120
    static let keepResolvedFor: TimeInterval = 30 * 86_400
    static let keepPendingFor: TimeInterval = 90 * 86_400
    static let mostKept = 500

    /// Waiting payments, newest first.
    var pending: [PendingPayment] {
        payments.filter { $0.status == .pending }.sorted { $0.date > $1.date }
    }

    func payment(id: UUID) -> PendingPayment? {
        payments.first { $0.id == id }
    }

    func memory(for payment: PendingPayment) -> MerchantMemory? {
        merchants[payment.merchantKey]
    }

    /// Adds a payment, or returns the one already caught when the same tap arrives twice.
    @discardableResult
    mutating func capture(
        merchant: String, amount: Money, date: Date, source: PendingPayment.Source, now: Date
    ) -> (payment: PendingPayment, isNew: Bool) {
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = PendingPayment(
            id: UUID(),
            merchant: name.isEmpty ? String(localized: "Card Payment") : String(name.prefix(80)),
            amount: amount,
            date: date,
            source: source
        )
        if let existing = payments.first(where: {
            $0.merchantKey == candidate.merchantKey && $0.amount == amount
                && abs($0.date.timeIntervalSince(date)) <= Self.duplicateWindow
        }) {
            return (existing, false)
        }
        payments.append(candidate)
        if source == .wallet { lastWalletCaptureAt = now }
        prune(now: now)
        return (candidate, true)
    }

    /// Marks a payment split or yours alone and learns from it. Returns true when this merchant has just been muted.
    @discardableResult
    mutating func resolve(
        id: UUID, as status: PendingPayment.Status, expenseID: UUID? = nil, groupID: UUID? = nil,
        category: ExpenseCategory? = nil, learns: Bool = true, now: Date
    ) -> Bool {
        guard status != .pending, let index = payments.firstIndex(where: { $0.id == id }),
              payments[index].status == .pending else { return false }
        payments[index].status = status
        payments[index].resolvedAt = now
        payments[index].expenseID = expenseID
        guard learns else {
            prune(now: now)
            return false
        }
        let key = payments[index].merchantKey
        var memory = merchants[key] ?? MerchantMemory()
        var justMuted = false
        switch status {
        case .split:
            memory.splitCount += 1
            memory.dismissCount = 0
            memory.isMuted = false
            if let groupID { memory.groupID = groupID }
            if let category { memory.category = category }
        case .dismissed:
            memory.dismissCount += 1
            if memory.dismissCount >= 2, memory.splitCount == 0, !memory.isMuted {
                memory.isMuted = true
                justMuted = true
            }
        case .pending:
            break
        }
        merchants[key] = memory
        prune(now: now)
        return justMuted
    }

    mutating func setMuted(_ muted: Bool, merchantKey: String) {
        var memory = merchants[merchantKey] ?? MerchantMemory()
        memory.isMuted = muted
        if !muted { memory.dismissCount = 0 }
        merchants[merchantKey] = memory
    }

    /// The same merchant charged the same amount at least 20 days apart: a subscription or a bill, not something to share.
    func isRecurring(_ payment: PendingPayment) -> Bool {
        payments.contains {
            $0.id != payment.id && $0.merchantKey == payment.merchantKey && $0.amount == payment.amount
                && abs($0.date.timeIntervalSince(payment.date)) >= 20 * 86_400
        }
    }

    /// Forgets what is old enough not to matter, so the file stays small.
    mutating func prune(now: Date) {
        payments.removeAll { payment in
            switch payment.status {
            case .pending: now.timeIntervalSince(payment.date) > Self.keepPendingFor
            case .split, .dismissed: now.timeIntervalSince(payment.resolvedAt ?? payment.date) > Self.keepResolvedFor
            }
        }
        if payments.count > Self.mostKept {
            payments = Array(payments.sorted { $0.date > $1.date }.prefix(Self.mostKept))
        }
    }
}

/// A merchant name reduced to the words that stay the same between visits: "STARBUCKS #1234" and "Starbucks" match.
enum MerchantKey {
    static func make(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in word.unicodeScalars.contains { CharacterSet.letters.contains($0) } }
            .joined(separator: " ")
    }
}
