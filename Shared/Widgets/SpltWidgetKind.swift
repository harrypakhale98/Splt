import Foundation

/// Shared names between the app and its widgets.
enum SpltWidgetKind {
    static let inbox = "com.harrypakhale.splt.inbox"
    static let addExpenseControl = "com.harrypakhale.splt.add-expense-control"
    static let splitLastPaymentControl = "com.harrypakhale.splt.split-last-payment-control"
    static let balance = "com.harrypakhale.splt.balance"

    /// The app's links, written out here because the widgets can't see `DeepLink`.
    static let activityURL = URL(string: "splt://activity")!
    static let addExpenseURL = URL(string: "splt://add-expense")!
    static let friendsURL = URL(string: "splt://friends")!

    static func friendURL(_ id: UUID) -> URL {
        URL(string: "splt://friend/\(id.uuidString)")!
    }

    static func paymentURL(_ id: UUID) -> URL {
        URL(string: "splt://payment/\(id.uuidString)")!
    }
}
