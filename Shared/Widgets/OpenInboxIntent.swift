import AppIntents
import Foundation
import UserNotifications
import WidgetKit

// Built into the app and the widgets, so a widget or control can run them and the app opens where it should.

/// Opens Splt on the To Split list.
struct OpenInboxIntent: AppIntent {
    static let title: LocalizedStringResource = "Open To Split"
    static let description = IntentDescription("Opens the payments waiting to be split.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(SpltWidgetKind.activityURL))
    }
}

/// Opens a new expense, for the Add Expense control. Siri and Shortcuts use `AddExpenseIntent` instead.
struct OpenAddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "New Expense"
    static let description = IntentDescription("Opens a new expense.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(SpltWidgetKind.addExpenseURL))
    }
}

/// Opens Splt on the newest payment waiting to be split.
struct SplitLastPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Split Last Payment"
    static let description = IntentDescription("Opens the newest payment in To Split, ready to split.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let newest = PaymentInboxFile.shared.read().pending.first
        return .result(opensIntent: OpenURLIntent(newest.map { SpltWidgetKind.paymentURL($0.id) } ?? SpltWidgetKind.activityURL))
    }
}

/// Marks a payment as not shared, from the To Split widget, without opening the app. It changes only the
/// inbox file, so it works in the widget, and the app catches up the next time it comes forward.
struct NotSharedIntent: AppIntent {
    static let title: LocalizedStringResource = "Not Shared"
    static let description = IntentDescription("Marks a payment in To Split as yours alone.")
    static let isDiscoverable = false
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Payment")
    var paymentID: String

    init() {}

    init(paymentID: UUID) {
        self.paymentID = paymentID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: paymentID) else { return .result() }
        PaymentInboxFile.shared.update { $0.resolve(id: id, as: .dismissed, now: Date()) }
        let nudge = [PendingPayment.notificationID(for: id)]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: nudge)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: nudge)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

extension PendingPayment {
    /// The nudge about one payment, so whoever resolves it can take the nudge back.
    static func notificationID(for id: UUID) -> String { "splt.payment.\(id.uuidString)" }
}
