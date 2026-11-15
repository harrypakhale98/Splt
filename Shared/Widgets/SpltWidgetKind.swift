import Foundation

/// Shared names between the app and its widgets.
enum SpltWidgetKind {
    static let inbox = "com.harrypakhale.splt.inbox"
    static let inboxControl = "com.harrypakhale.splt.inbox-control"
    static let addExpenseControl = "com.harrypakhale.splt.add-expense-control"
    static let splitLastPaymentControl = "com.harrypakhale.splt.split-last-payment-control"

    /// The app's links, written out here because the widgets can't see `DeepLink`.
    static let activityURL = URL(string: "splt://activity")!
    static let addExpenseURL = URL(string: "splt://add-expense")!

    static func paymentURL(_ id: UUID) -> URL {
        URL(string: "splt://payment/\(id.uuidString)")!
    }
}
