import Foundation
import SpltCore

/// Where you stand, as the app last worked it out, kept where the Your Balance widget can read it.
/// The widget can't open the app's store, so the app saves this after every change and sync.
struct BalanceWidgetSnapshot: Codable, Hashable, Sendable {
    /// A friend you have money with, for the medium widget's rows.
    struct Friend: Codable, Hashable, Sendable, Identifiable {
        var id: UUID
        var name: String
        /// Signed, one amount per currency: positive when they owe you.
        var balance: [Money]
        /// Their avatar as the app draws it: initials on their person color.
        var initials: String
        var color: PersonColor
    }

    /// A person's color in light and dark, with the text that reads on it, as hex values.
    struct PersonColor: Codable, Hashable, Sendable {
        var lightFill: UInt32
        var lightText: UInt32
        var darkFill: UInt32
        var darkText: UInt32
    }

    static let key = "widgets.balance"
    /// The most friends any size shows.
    static let mostFriends = 3

    /// Each one positive amount per currency, as in the Friends tab hero.
    var owedToYou: [Money] = []
    var youOwe: [Money] = []
    /// The friends with the largest balances, largest first.
    var friends: [Friend] = []
    /// The Face ID lock is on, so nothing here names a person or an amount.
    var hidesDetails = false

    var position: NetPosition { NetPosition(owedToYou: owedToYou, youOwe: youOwe) }

    /// With the lock on, the snapshot keeps nothing that could be read from the widget.
    static let hidden = BalanceWidgetSnapshot(hidesDetails: true)

    static func load(from defaults: UserDefaults) -> BalanceWidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(BalanceWidgetSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
