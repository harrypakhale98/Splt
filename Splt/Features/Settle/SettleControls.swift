import SpltCore
import SwiftUI

/// Everything you set before recording: how much, paid with what, when, and the payment app.
struct SettleControls: View {
    let model: SettleModel
    let onPayWith: (URL) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if model.isBatch {
            batchCard
        } else {
            amountCard
        }
        methodRow
        detailsCard
        payWithButton
    }

    // MARK: Amount

    private var amountCard: some View {
        @Bindable var model = model

        return SettleCard {
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
            SettleChip(title: "Full", symbol: "circle.fill", selected: model.amountMode == .full) {
                model.amountMode = .full
            }
            SettleChip(title: "Partial", symbol: "circle.lefthalf.filled", selected: model.amountMode == .partial) {
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
        SettleCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Payments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(model.route.debts, id: \.self) { debt in
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        AvatarView(name: model.avatarName(of: debt.debtor), id: debt.debtor, members: model.participants.map(\.id), size: 32)
                        Text(model.sentence(payer: debt.debtor, receiver: debt.creditor))
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        MoneyLabel(money: debt.amount)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Each payment is recorded so the group ends up square.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Method, date and note

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
                            SettleChip(title: method.title, symbol: method.symbol, selected: model.method == method) {
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

        return SettleCard {
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
                    onPayWith(url)
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
}

/// A rounded card on the grouped background.
struct SettleCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A glass chip that can be selected. Its whole capsule is the target and VoiceOver reads the title.
struct SettleChip: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
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
}
