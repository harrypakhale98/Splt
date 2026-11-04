import SpltCore
import SwiftUI

/// Records a payment, or every suggested payment of a group. Presented with a `SettleRoute`.
struct SettleUpSheet: View {
    let route: SettleRoute

    @Environment(\.dataServices) private var services

    var body: some View {
        if let services {
            SettleUpContent(route: route, services: services)
        } else {
            NavigationStack {
                EmptyStateView(
                    title: "Can't Settle Up",
                    systemImage: "exclamationmark.triangle",
                    description: "Splt couldn't open its storage."
                )
            }
        }
    }
}

private struct SettleUpContent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.settleUndo) private var undoCenter
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    @State private var model: SettleModel
    @State private var ceremony = SettleCeremony.idle
    @State private var payWithFailed = false
    @State private var detent = PresentationDetent.large

    @Environment(\.dynamicTypeSize) private var typeSize

    /// A short sheet for the receipt, or the full height when large text needs the room.
    private var receiptDetent: PresentationDetent {
        typeSize.isAccessibilitySize ? .large : .fraction(0.72)
    }

    init(route: SettleRoute, services: DataServices) {
        _model = State(initialValue: SettleModel(route: route, services: services))
    }

    private var hasRecorded: Bool { model.receipt != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettleHeroCard(model: model, ceremony: ceremony)
                    if ceremony.finished {
                        SettleDoneCard(model: model, finished: ceremony.finished)
                    } else if !hasRecorded {
                        SettleControls(model: model, onPayWith: { url in Task { await payWith(url) } })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !hasRecorded { recordBar }
            }
            .task(id: model.receipt?.id) { await runCeremony() }
            .alert("Couldn't Record Payment", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .confirmationDialog(
                "Can't Open \(model.method.title)", isPresented: $payWithFailed, titleVisibility: .visible
            ) {
                payWithFallbackActions
            } message: {
                Text("\(model.method.title) isn't installed or can't be opened here. You can copy the amount to use somewhere else, or record the payment now and pay later.")
            }
        }
        .presentationDetents([.large, receiptDetent], selection: $detent)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !hasRecorded {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
        } else if ceremony.finished {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: finish)
            }
        }
    }

    /// The button rides on a bar, so the form scrolls underneath it instead of showing through.
    private var recordBar: some View {
        Button {
            model.record()
        } label: {
            Text("Record Payment")
                .font(.headline)
                .foregroundStyle(PersonPalette.onColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!model.canRecord)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Ceremony

    /// Plays the settle moment when a payment is recorded, then closes by itself. Undoing resets it.
    private func runCeremony() async {
        guard let receipt = model.receipt else {
            withAnimation(Motion.animation(.smooth, reduceMotion: reduceMotion)) {
                ceremony = .idle
                detent = .large
            }
            return
        }
        withAnimation(Motion.animation(.smooth, reduceMotion: reduceMotion)) { detent = receiptDetent }
        await SettleCeremony.play(on: $ceremony, reduceMotion: reduceMotion)
        AccessibilityNotification.Announcement(receipt.message).post()
        guard !voiceOverOn else { return }
        try? await Task.sleep(for: SettleTiming.confirmation)
        if model.receipt?.id == receipt.id { finish() }
    }

    private var payWithFallbackActions: some View {
        Group {
            if let amount = model.amount {
                Button("Copy Amount") {
                    UIPasteboard.general.string = amount.plainString(locale: locale)
                }
            }
            if let website = model.method.websiteURL {
                Button("Open \(model.method.title) Website") { openURL(website) }
            }
            if model.canRecord {
                Button("Record Payment") { model.record() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func payWith(_ url: URL) async {
        if await PayWithLauncher().launch(url) == .unavailable {
            payWithFailed = true
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private func finish() {
        if let receipt = model.receipt { undoCenter?.show(receipt) }
        dismiss()
    }
}

#if DEBUG
#Preview("One payment") {
    let services = SampleData.previewServices()
    let debt = (try? services.groups.balances(for: GroupID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000102")!)).suggestedSettlements.first) ?? nil
    SettleUpSheet(route: SettleRoute(groupID: GroupID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000102")!), debts: debt.map { [$0] } ?? []))
        .environment(\.dataServices, services)
}

#Preview("Whole group") {
    let services = SampleData.previewServices()
    let id = GroupID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!)
    let debts = (try? services.groups.balances(for: id).suggestedSettlements) ?? []
    SettleUpSheet(route: SettleRoute(groupID: id, debts: debts))
        .environment(\.dataServices, services)
}
#endif
