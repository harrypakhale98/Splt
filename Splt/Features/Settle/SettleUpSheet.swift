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
    @State private var payWithFailed = false
    @State private var contraction: CGFloat = 0
    @State private var ring: CGFloat = 0
    @State private var rolled = false
    @State private var finished = false

    init(route: SettleRoute, services: DataServices) {
        _model = State(initialValue: SettleModel(route: route, services: services))
    }

    private var hasRecorded: Bool { model.receipt != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    if finished {
                        doneCard
                    } else if !hasRecorded {
                        controls
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !hasRecorded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                } else if finished {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: finish)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
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
        .presentationDetents([.large])
    }

    // MARK: Hero

    private var shownAmount: Money? {
        guard let amount = model.amount ?? model.totals.first else { return nil }
        return rolled ? Money.zero(currencyCode: amount.currencyCode) : amount
    }

    private var heroCard: some View {
        VStack(spacing: 10) {
            SettleStage(
                layout: stageLayout, fraction: model.fraction, isAdjustable: canDrag,
                contraction: contraction, ring: ring,
                onFraction: { model.setFraction($0) }, onStep: { model.nudge(by: $0) }
            )
            if finished {
                Text(model.remaining == nil ? String(localized: "All square") : String(localized: "Paid in part"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                Text(model.headline)
                    .font(.headline)
            }
            if let shownAmount {
                HeroAmount(shownAmount, showsSign: false)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Amount \(MoneyFormatting.magnitudeString(shownAmount, locale: locale))"))
            }
            if !rolled, let remaining = model.remaining {
                Text("\(MoneyFormatting.magnitudeString(remaining, locale: locale)) will still be owed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background {
            ZStack {
                Color(.secondarySystemGroupedBackground)
                GroupGradient(colors: model.participants.map(\.color)).opacity(0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }

    private var stageLayout: SettleStage.Layout {
        let people = model.participants
        if people.count == 2, !model.isBatch { return .pair(payer: people[0], receiver: people[1]) }
        return .group(people)
    }

    private var canDrag: Bool {
        !model.isBatch && !model.isReversed && !hasRecorded && model.fullAmount.map { $0.minorUnits > model.step } ?? false
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if model.isBatch {
            batchCard
        } else {
            amountCard
        }
        methodRow
        detailsCard
        payWithButton
    }

    private var amountCard: some View {
        @Bindable var model = model

        return card {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { amountChips }
                    VStack(alignment: .leading, spacing: 8) { amountChips }
                }
                if model.amountMode == .partial {
                    HStack(spacing: 12) {
                        stepButton("minus", label: "Less", steps: -1)
                        TextField("Amount", text: $model.amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .accessibilityLabel("Amount to pay in \(model.fullAmount?.currencyCode ?? "")")
                        stepButton("plus", label: "More", steps: 1)
                    }
                    .transition(.opacity)
                }
                if let footer = amountMessage {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .motion(.smooth, value: model.amountMode)
        }
    }

    @ViewBuilder
    private var amountChips: some View {
        if model.fullAmount != nil {
            chip(title: "Full", symbol: "circle.fill", selected: model.amountMode == .full) {
                model.amountMode = .full
            }
            chip(title: "Partial", symbol: "circle.lefthalf.filled", selected: model.amountMode == .partial) {
                model.setFraction(0.5)
            }
            Spacer(minLength: 0)
            Button {
                model.isReversed.toggle()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Swap who pays")
            .accessibilityAddTraits(model.isReversed ? .isSelected : [])
            .haptics(.tick, trigger: model.isReversed)
        }
    }

    private func chip(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GlassPill(tint: selected ? .accentColor : nil, isInteractive: true) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .haptics(.tick, trigger: selected)
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, steps: Int) -> some View {
        Button {
            model.nudge(by: steps)
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    private var amountMessage: String? {
        guard let issue = model.amountIssue else {
            return model.isReversed ? String(localized: "This records a payment the other way, such as an advance.") : nil
        }
        switch issue {
        case .empty: return String(localized: "Enter how much was paid.")
        case .invalid: return String(localized: "That isn't an amount.")
        case .notPositive: return String(localized: "The amount must be more than zero.")
        case .exceedsBalance(let limit):
            let owed = MoneyFormatting.magnitudeString(limit, locale: locale)
            return String(localized: "That's more than the \(owed) owed. Swap the direction to record an advance.")
        }
    }

    private var batchCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Payments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(model.route.debts, id: \.self) { debt in
                    HStack(spacing: 12) {
                        AvatarView(name: model.name(of: debt.debtor), id: debt.debtor, members: model.participants.map(\.id), size: 32)
                        Text(model.sentence(payer: debt.debtor, receiver: debt.creditor))
                        Spacer(minLength: 8)
                        MoneyLabel(money: debt.amount)
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Each payment is recorded so the group ends up square.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var methodRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paid with")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(SettleMethod.allCases) { method in
                            chip(title: method.title, symbol: method.symbol, selected: model.method == method) {
                                model.method = method
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, -20)
    }

    private var detailsCard: some View {
        @Bindable var model = model

        return card {
            VStack(spacing: 12) {
                DatePicker("Date", selection: $model.date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date)
                Divider()
                TextField("Note", text: $model.note, axis: .vertical)
                    .lineLimit(1...3)
            }
        }
    }

    @ViewBuilder
    private var payWithButton: some View {
        if let url = model.payWithURL {
            VStack(spacing: 6) {
                Button {
                    Task { await payWith(url) }
                } label: {
                    Label("Pay with \(model.method.title)", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                Text("Opens \(model.method.title) so you can send the money. Come back and tap Record Payment when it's done.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var recordBar: some View {
        Button {
            model.record()
        } label: {
            Text("Record Payment")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!model.canRecord)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Done

    private var doneCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : finished)
                .accessibilityHidden(true)
            Text("Payment Recorded")
                .font(.title3.weight(.semibold))
            if let receipt = model.receipt {
                Text(receipt.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Undo") { model.undo() }
                .buttonStyle(.glass)
                .controlSize(.large)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    // MARK: Ceremony

    /// One calm second: the arc contracts, a ring closes around both people and the amount rolls to zero.
    private func runCeremony() async {
        guard let receipt = model.receipt else {
            withAnimation(Motion.animation(.smooth, reduceMotion: reduceMotion)) {
                contraction = 0
                ring = 0
                rolled = false
                finished = false
            }
            return
        }
        Haptics.play(.settle, reduceMotion: reduceMotion)
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.3)) {
                contraction = 1
                ring = 1
                rolled = true
                finished = true
            }
        } else {
            withAnimation(.easeIn(duration: 0.35)) { contraction = 1 }
            try? await Task.sleep(for: .milliseconds(280))
            withAnimation(.easeOut(duration: 0.4)) { ring = 1 }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.smooth(duration: 0.6)) { rolled = true }
            try? await Task.sleep(for: .milliseconds(560))
            withAnimation(.smooth) { finished = true }
        }
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

    // MARK: Actions

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
