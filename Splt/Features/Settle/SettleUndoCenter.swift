import Observation
import SwiftUI

/// Holds the payment that was just recorded so a banner can offer to undo it for a few seconds.
/// The activity feed offers the same undo later.
@MainActor
@Observable
final class SettleUndoCenter {
    enum Banner: Equatable {
        case recorded(SettleReceipt)
        case undone(String)

        var message: String {
            switch self {
            case .recorded(let receipt): receipt.message
            case .undone(let text): text
            }
        }
    }

    private(set) var banner: Banner?

    @ObservationIgnored private let visibleFor: Duration
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    init(visibleFor: Duration = .seconds(8)) {
        self.visibleFor = visibleFor
    }

    func show(_ receipt: SettleReceipt) {
        present(.recorded(receipt))
    }

    /// Reverses the recorded payments and says so. Returns false if nothing was showing.
    @discardableResult
    func undo(using payments: any PaymentRepository) -> Bool {
        guard case .recorded(let receipt) = banner else { return false }
        var failed = false
        for id in receipt.paymentIDs {
            do { try payments.undo(id: id) } catch { failed = true }
        }
        present(.undone(failed ? String(localized: "Couldn't undo the payment") : String(localized: "Payment undone")))
        return !failed
    }

    func dismiss() {
        hideTask?.cancel()
        banner = nil
    }

    private func present(_ banner: Banner) {
        hideTask?.cancel()
        self.banner = banner
        AccessibilityNotification.Announcement(banner.message).post()
        hideTask = Task { [visibleFor] in
            try? await Task.sleep(for: visibleFor)
            guard !Task.isCancelled else { return }
            self.banner = nil
        }
    }
}

extension EnvironmentValues {
    /// Set once by the app root. Nil in a bare preview, where nothing offers an undo.
    @Entry var settleUndo: SettleUndoCenter?
}
