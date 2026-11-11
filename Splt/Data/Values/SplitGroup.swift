import Foundation
import SpltCore

/// A group of people who share costs. Named `SplitGroup` so it never collides with SwiftUI's `Group`.
struct SplitGroup: Hashable, Sendable, Codable, Identifiable {
    var id: GroupID
    var name: String
    /// An SF Symbol name.
    var symbol: String
    var currencyCode: String
    var kind: GroupKind
    /// In display order.
    var memberIDs: [PersonID]
    var simplifiesDebts: Bool
    var isArchived: Bool
    var tripStart: Date?
    var tripEnd: Date?
    var pinnedRate: PinnedRate?
    /// The cover photo's file name in `PhotoStore.covers`, or nil to show the symbol.
    /// Changes through `GroupRepository.setCover` and `removeCover`, never through `update`.
    var coverFileName: String?
    /// How a new expense starts out split. Nil splits equally. Changes through `GroupRepository.setDefaultSplit`.
    var defaultSplit: DefaultSplit?
    var createdAt: Date

    init(
        id: GroupID = GroupID(),
        name: String,
        symbol: String = "person.3.fill",
        currencyCode: String,
        kind: GroupKind = .standard,
        memberIDs: [PersonID] = [],
        simplifiesDebts: Bool = true,
        isArchived: Bool = false,
        tripStart: Date? = nil,
        tripEnd: Date? = nil,
        pinnedRate: PinnedRate? = nil,
        coverFileName: String? = nil,
        defaultSplit: DefaultSplit? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.currencyCode = currencyCode.uppercased()
        self.kind = kind
        self.memberIDs = memberIDs
        self.simplifiesDebts = simplifiesDebts
        self.isArchived = isArchived
        self.tripStart = tripStart
        self.tripEnd = tripEnd
        self.pinnedRate = pinnedRate
        self.coverFileName = coverFileName
        self.defaultSplit = defaultSplit
        self.createdAt = createdAt
    }

    /// The cover to show. A two-person friend group never shows one, whatever a synced record says.
    var shownCoverFileName: String? {
        kind == .friend ? nil : coverFileName
    }
}
