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
    @Environment(\.locale) private var locale

    @State private var model: SettleModel
    @State private var payWithFailed = false
    @FocusState private var amountFocused: Bool

    init(route: SettleRoute, services: DataServices) {
        _model = State(initialValue: SettleModel(route: route, services: services))
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Group {
                if let receipt = model.receipt {
                    SettleConfirmationView(message: receipt.message, onUndo: { model.undo() })
                        .task(id: receipt.id) {
                            guard !voiceOverOn else { return }
                            try? await Task.sleep(for: SettleTiming.confirmation)
                            if model.receipt?.id == receipt.id { finish() }
                        }
                } else {
                    form
                }
            }
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.receipt == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Record Payment") { model.record() }
                            .disabled(!model.canRecord)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: finish)
                    }
                }
            }
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

    private var form: some View {
        Form {
            summarySection
            if model.isBatch {
                batchSection
            } else {
                amountSection
                directionSection
            }
            detailsSection
            payWithSection
        }
    }

    // MARK: Sections

    private var summarySection: some View {
        Section {
            VStack(spacing: 8) {
                if let payer = model.payer, let receiver = model.receiver {
                    HStack(spacing: -8) {
                        AvatarView(name: model.name(of: payer), size: 48)
                        AvatarView(name: model.name(of: receiver), size: 48)
                    }
                    .accessibilityHidden(true)
                }
                Text(model.headline)
                    .font(.headline)
                if let amount = model.amount {
                    MoneyLabel(money: amount)
                        .font(.largeTitle.bold())
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    private var batchSection: some View {
        Section {
            ForEach(model.route.debts, id: \.self) { debt in
                HStack {
                    Text(model.sentence(payer: debt.debtor, receiver: debt.creditor))
                    Spacer(minLength: 8)
                    MoneyLabel(money: debt.amount)
                        .font(.body.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Payments")
        } footer: {
            Text("Each payment is recorded so the group ends up square.")
        }
    }

    @ViewBuilder
    private var amountSection: some View {
        @Bindable var model = model

        Section {
            Picker("Amount", selection: $model.amountMode) {
                Text("Full Amount").tag(SettleModel.AmountMode.full)
                Text("Partial").tag(SettleModel.AmountMode.partial)
            }
            .pickerStyle(.segmented)
            if model.amountMode == .partial, let full = model.fullAmount {
                LabeledContent("Amount") {
                    TextField("Amount", text: $model.amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($amountFocused)
                        .accessibilityLabel("Amount to pay in \(full.currencyCode)")
                }
            }
        } footer: {
            amountFooter
        }
    }

    @ViewBuilder
    private var amountFooter: some View {
        if let issue = model.amountIssue {
            switch issue {
            case .empty: Text("Enter how much was paid.")
            case .invalid: Text("That isn't an amount.")
            case .notPositive: Text("The amount must be more than zero.")
            case .exceedsBalance(let limit):
                Text("That's more than the \(MoneyFormatting.magnitudeString(limit, locale: locale)) owed. Switch the direction to record an advance.")
            }
        } else if let remaining = model.remaining {
            Text("\(MoneyFormatting.magnitudeString(remaining, locale: locale)) will still be owed.")
        }
    }

    @ViewBuilder
    private var directionSection: some View {
        @Bindable var model = model

        Section("Who Paid") {
            Picker("Direction", selection: $model.isReversed) {
                ForEach(model.directionOptions) { option in
                    Text(option.title).tag(option.reversed)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var detailsSection: some View {
        @Bindable var model = model

        return Section {
            DatePicker("Date", selection: $model.date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date)
            Picker(selection: $model.method) {
                ForEach(SettleMethod.allCases) { method in
                    Label(method.title, systemImage: method.symbol).tag(method)
                }
            } label: {
                Text("Method")
            }
            TextField("Note", text: $model.note, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    @ViewBuilder
    private var payWithSection: some View {
        if let url = model.payWithURL {
            Section {
                Button {
                    Task { await payWith(url) }
                } label: {
                    Label("Pay with \(model.method.title)", systemImage: "arrow.up.forward.app")
                }
            } footer: {
                Text("Opens \(model.method.title) so you can send the money. Come back and tap Record Payment when it's done.")
            }
        }
    }

    @ViewBuilder
    private var payWithFallbackActions: some View {
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
