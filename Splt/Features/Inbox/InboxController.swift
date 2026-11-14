import Foundation
import Observation
import SpltCore

/// What the To Split list on the Activity tab shows and does. Owned by the Activity screen, so the
/// list's rows and the sheets they open share one source.
@MainActor
@Observable
final class InboxController {
    let services: DataServices
    let inbox: PaymentInbox

    private(set) var review: InboxReview?
    var showsEverythingElse = false
    var editing: InboxEditing?
    var wrapping: InboxReview.WrapUp?
    var showsSetup = false
    /// A merchant that was just muted, with a chance to undo.
    var mutedNotice: PendingPayment?
    var errorMessage: String?

    init(services: DataServices, inbox: PaymentInbox = .shared) {
        self.services = services
        self.inbox = inbox
        inbox.services = services
    }

    func update(now: Date = Date()) {
        review = InboxReview(state: inbox.state, services: services, now: now)
    }

    /// Opens the expense form filled in from the payment. False when there is no group to put it in yet.
    @discardableResult
    func open(_ row: InboxReview.Row) -> Bool {
        guard let target = row.target else { return false }
        editing = InboxEditing(payment: row.payment, groupID: target.id, category: row.category)
        return true
    }

    @discardableResult
    func openPayment(_ id: UUID) -> Bool {
        guard let row = review?.row(for: id) else { return false }
        return open(row)
    }

    func quickSplit(_ row: InboxReview.Row) {
        guard let target = row.target else { return }
        do {
            try inbox.split(row.payment, into: target, services: services)
        } catch {
            errorMessage = String(localized: "Splt couldn't add \(row.payment.merchant). Please try again.")
        }
    }

    func dismiss(_ row: InboxReview.Row) {
        if mutedNotice?.id != row.payment.id { mutedNotice = nil }
        if inbox.dismiss(row.payment.id) { mutedNotice = row.payment }
    }

    func undoMute() {
        if let payment = mutedNotice { inbox.setMuted(false, merchantKey: payment.merchantKey) }
        mutedNotice = nil
    }

    func saved(_ expense: Expense, for payment: PendingPayment) {
        inbox.markSplit(payment.id, expense: expense)
    }

    /// Splits the kept payments into the trip and marks the rest as yours alone, without muting their merchants.
    /// Stops at the first one that can't be saved and returns false.
    func wrapUp(_ wrapUp: InboxReview.WrapUp, keeping kept: Set<UUID>) -> Bool {
        for payment in wrapUp.payments {
            if kept.contains(payment.id) {
                guard (try? inbox.split(payment, into: wrapUp.trip, services: services)) != nil else {
                    errorMessage = String(localized: "Splt couldn't add \(payment.merchant). Please try again.")
                    return false
                }
            } else {
                inbox.dismiss(payment.id, learns: false)
            }
        }
        return true
    }
}

/// A payment open in the expense form.
struct InboxEditing: Identifiable, Hashable {
    let payment: PendingPayment
    let groupID: GroupID
    let category: ExpenseCategory?

    var id: UUID { payment.id }

    var draft: ExpenseDraft {
        ExpenseDraft(title: payment.merchant, total: payment.amount, date: payment.date, category: category)
    }
}
