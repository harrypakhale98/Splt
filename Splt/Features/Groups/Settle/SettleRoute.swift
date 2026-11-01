import Foundation
import SpltCore

/// What to settle, handed from the group screens to whichever sheet records the payment.
struct SettleRoute: Identifiable, Hashable, Sendable {
    let id = UUID()
    var groupID: GroupID
    /// One debt when someone tapped a row, or every suggested payment for "Settle Up".
    var debts: [Debt]
}
