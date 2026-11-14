import SpltCore
import SwiftUI

/// The To Split list at the top of Activity: payments caught from Wallet, bank texts and screenshots,
/// waiting to be split or kept. Nothing shows until there is something to decide.
struct InboxSection: View {
    let controller: InboxController

    @Environment(Router.self) private var router
    @AppStorage(PaymentInbox.manualAddsKey) private var manualAdds = 0
    @AppStorage(PaymentInbox.offerDismissedKey) private var offerDismissed = false

    var body: some View {
        if let review = controller.review, hasContent(review) {
            Section {
                RaisedRows(padding: EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)) {
                    ForEach(review.wrapUps) { wrapUp in
                        wrapUpRow(wrapUp)
                    }
                    if showsOffer {
                        offerRow
                    }
                    ForEach(review.toSplit) { row in
                        paymentRow(row)
                    }
                    if !review.everythingElse.isEmpty {
                        everythingElseToggle(count: review.everythingElse.count)
                        if controller.showsEverythingElse {
                            ForEach(review.everythingElse) { row in
                                paymentRow(row)
                            }
                        }
                    }
                    if let muted = controller.mutedNotice {
                        mutedRow(muted)
                    }
                    if !review.rows.isEmpty {
                        Button("Missed One? Add It") { router.present(.addExpense) }
                            .font(.subheadline)
                            .foregroundStyle(Ink.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityIdentifier("inbox.addMissed")
                    }
                }
            } header: {
                Text("To Split")
                    .sectionHeaderStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Depth.pageMargin + 4)
                    .padding(.vertical, 6)
                    .background(Ink.paper)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    private func hasContent(_ review: InboxReview) -> Bool {
        !review.rows.isEmpty || !review.wrapUps.isEmpty || showsOffer || controller.mutedNotice != nil
    }

    /// Setup is offered once you have added a few expenses by hand and Wallet hasn't sent anything yet.
    private var showsOffer: Bool {
        manualAdds >= 3 && controller.inbox.state.lastWalletCaptureAt == nil && !offerDismissed
    }

    private func paymentRow(_ row: InboxReview.Row) -> some View {
        Button {
            if !controller.open(row) { router.present(.newGroup) }
        } label: {
            InboxRowView(row: row)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            if let target = row.target {
                Button("Split with \(SettleLeg.displayName(of: target))", systemImage: "person.2") {
                    Motion.perform(Motion.smooth) { controller.quickSplit(row) }
                }
                .tint(Ink.owed)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Mine", systemImage: "person") {
                Motion.perform(Motion.smooth) { controller.dismiss(row) }
            }
            .tint(Ink.secondary)
        }
        .accessibilityAction(named: "Mine") { controller.dismiss(row) }
    }

    private func wrapUpRow(_ wrapUp: InboxReview.WrapUp) -> some View {
        Button {
            controller.wrapping = wrapUp
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "suitcase.rolling")
                    .foregroundStyle(Ink.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wrap Up \(wrapUp.trip.name)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Ink.text)
                    Text("^[\(wrapUp.payments.count) payment](inflect: true) from the trip, split in one go")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var offerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You've added \(manualAdds) expenses by hand. Splt can catch Apple Pay payments as you pay, so they're waiting here.")
                .font(.subheadline)
                .foregroundStyle(Ink.text)
            HStack(spacing: 16) {
                Button("Set Up") { controller.showsSetup = true }
                    .font(.subheadline.weight(.semibold))
                Button("Not Now") { Motion.perform(Motion.smooth) { offerDismissed = true } }
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
        }
        .padding(.top, 10)
    }

    private func everythingElseToggle(count: Int) -> some View {
        Button {
            Motion.perform(Motion.smooth) { controller.showsEverythingElse.toggle() }
        } label: {
            HStack {
                Text("Everything Else (\(count))")
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                Spacer()
                Image(systemName: controller.showsEverythingElse ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(controller.showsEverythingElse ? String(localized: "Shown") : String(localized: "Hidden"))
    }

    private func mutedRow(_ payment: PendingPayment) -> some View {
        HStack {
            Text("Splt won't ask about \(payment.merchant) again.")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
            Spacer(minLength: 8)
            Button("Undo") { controller.undoMute() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .frame(minHeight: 44)
    }
}

/// One payment: where, when and where it would go on the left, the amount on the right.
struct InboxRowView: View {
    let row: InboxReview.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.payment.merchant)
                    .font(.body)
                    .foregroundStyle(Ink.text)
                    .lineLimit(2)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 8)
            Text(MoneyFormatting.magnitudeString(row.payment.amount))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(Ink.text)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.payment.merchant), \(MoneyFormatting.magnitudeString(row.payment.amount)), \(caption)")
        .accessibilityHint("Opens the expense, filled in. Swipe to split or keep it.")
    }

    private var caption: String {
        let when = row.payment.date.formatted(.relative(presentation: .named))
        guard let target = row.target else { return when }
        return String(localized: "\(when) · \(SettleLeg.displayName(of: target))")
    }

    private var symbol: String {
        switch row.payment.source {
        case .wallet: "wallet.pass"
        case .text: "message"
        case .screenshot: "photo"
        }
    }
}

/// The inbox's sheets, alert and refresh, attached to the Activity list.
struct InboxPresentation: ViewModifier {
    @Bindable var controller: InboxController
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        @Bindable var router = router
        content
            .task(id: controller.inbox.state) {
                controller.update()
                openPending()
            }
            .onAppear { controller.inbox.refresh() }
            .onChange(of: router.pendingPayment) { openPending() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { controller.inbox.refresh() }
            }
            .sheet(item: $controller.editing) { editing in
                ExpenseFormView(mode: .add(groupID: editing.groupID, prefill: editing.draft)) { expense in
                    controller.saved(expense, for: editing.payment)
                }
            }
            .sheet(item: $controller.wrapping) { wrapUp in
                TripWrapUpView(wrapUp: wrapUp, controller: controller)
            }
            .sheet(isPresented: $controller.showsSetup) {
                NavigationStack { PaymentCaptureSetupView(showsDone: true) }
            }
            .alert("Couldn't Split", isPresented: errorShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(controller.errorMessage ?? "")
            }
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })
    }

    /// A payment a notification or Siri asked to open, once the list knows about it.
    private func openPending() {
        guard let id = router.pendingPayment, controller.review != nil else { return }
        router.pendingPayment = nil
        if !controller.openPayment(id), controller.review?.row(for: id)?.target == nil,
           controller.review?.row(for: id) != nil {
            router.present(.newGroup)
        }
    }
}

extension View {
    func inboxPresentation(_ controller: InboxController) -> some View {
        modifier(InboxPresentation(controller: controller))
    }
}
