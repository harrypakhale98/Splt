import Foundation
import Observation
import SpltCore
import SwiftUI
import WidgetKit

/// The To Split list in the app. It reads and writes `PaymentInboxFile`, then brings notifications,
/// widgets and the trip Live Activity in line with it.
@MainActor
@Observable
final class PaymentInbox {
    static let shared = PaymentInbox(file: launchFile)

    /// UI tests start on an empty store, so they get an empty inbox too, whatever an earlier run left behind.
    private static var launchFile: PaymentInboxFile {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitesting") {
            return PaymentInboxFile(url: FileManager.default.temporaryDirectory.appending(path: "PaymentInbox-\(UUID().uuidString).json"))
        }
        #endif
        return .shared
    }

    /// How many manual expenses you have added, so setup is offered once it would help.
    static let manualAddsKey = "inbox.manualAdds"
    static let offerDismissedKey = "inbox.setupOfferDismissed"

    private(set) var state: PaymentInboxState
    @ObservationIgnored private let file: PaymentInboxFile
    @ObservationIgnored var now: () -> Date = { Date() }
    /// The data the app window uses. An intent that starts the app in the background falls back to the shared store.
    @ObservationIgnored var services: DataServices?
    /// Off in tests, so nothing is posted or reloaded.
    @ObservationIgnored var runsEffects = true

    init(file: PaymentInboxFile = .shared) {
        self.file = file
        self.state = file.read()
    }

    func reload() {
        let latest = file.read()
        if latest != state { state = latest }
    }

    func payment(id: UUID) -> PendingPayment? {
        state.payment(id: id)
    }

    @discardableResult
    func capture(merchant: String, amount: Money, date: Date, source: PendingPayment.Source) -> PendingPayment? {
        let now = now()
        guard let result = file.update({
            $0.capture(merchant: merchant, amount: amount, date: date, source: source, now: now)
        }) else { return nil }
        reload()
        if result.isNew { afterChange(new: result.payment) }
        return result.payment
    }

    /// Marks a payment as yours alone. Returns true when its merchant has just been muted.
    /// `learns` is false when a whole trip is wrapped up, where leaving one out says nothing about the merchant.
    @discardableResult
    func dismiss(_ id: UUID, learns: Bool = true) -> Bool {
        let now = now()
        let muted = file.update { $0.resolve(id: id, as: .dismissed, learns: learns, now: now) } ?? false
        reload()
        afterChange(resolved: id)
        return muted
    }

    /// Records the expense made from a payment, by the form or a quick split.
    func markSplit(_ id: UUID, expense: Expense) {
        let now = now()
        file.update {
            $0.resolve(
                id: id, as: .split, expenseID: expense.id.rawValue, groupID: expense.groupID?.rawValue,
                category: expense.category, now: now
            )
        }
        reload()
        afterChange(resolved: id)
    }

    /// Adds a payment to a group with its usual split, paid by you.
    @discardableResult
    func split(_ payment: PendingPayment, into group: SplitGroup, services: DataServices) throws -> Expense {
        let expense = try PaymentSplitter(services: services)
            .split(payment, into: group, category: state.memory(for: payment)?.category)
        markSplit(payment.id, expense: expense)
        return expense
    }

    func setMuted(_ muted: Bool, merchantKey: String) {
        file.update { $0.setMuted(muted, merchantKey: merchantKey) }
        reload()
        afterChange()
    }

    /// Picks up what an extension added and brings everything that shows the inbox up to date.
    func refresh() {
        reload()
        afterChange()
    }

    private func afterChange(new: PendingPayment? = nil, resolved: UUID? = nil) {
        guard runsEffects else { return }
        if let resolved { PaymentNotifier.cancel(resolved) }
        guard let services = services ?? IntentServices.shared.live() else {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let review = InboxReview(state: state, services: services, now: now())
        PaymentInboxFile.sharedDefaults.set(review.toSplit.count, forKey: PaymentInboxFile.toSplitCountKey)
        WidgetCenter.shared.reloadAllTimelines()
        TripLiveActivity.sync(review)
        Task {
            if let new, let row = review.row(for: new.id), row.priority == .high {
                await PaymentNotifier.nudge(row, delay: row.isInActiveTrip ? 5 : PaymentNotifier.pause)
            }
            await PaymentNotifier.refreshDigest(review)
            await PaymentNotifier.scheduleWrapUp(review)
        }
    }
}

private struct PaymentInboxRefresh: ViewModifier {
    let services: DataServices?
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                PaymentInbox.shared.services = services
                PaymentInbox.shared.refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                // payments shared from another app, the evening summary and the trip Live Activity all catch up here
                if phase == .active { PaymentInbox.shared.refresh() }
            }
    }
}

extension View {
    /// Keeps To Split, its notifications, widgets and trip Live Activity current whenever the app comes forward.
    func paymentInboxRefresh(services: DataServices?) -> some View {
        modifier(PaymentInboxRefresh(services: services))
    }
}
