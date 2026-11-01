import Foundation
import SpltCore

/// What was just recorded, kept so it can be undone.
struct SettleReceipt: Identifiable, Equatable, Sendable {
    let id = UUID()
    var paymentIDs: [PaymentID]
    /// A sentence such as "You paid Sam $12.50".
    var message: String
    var total: [Money]
}
