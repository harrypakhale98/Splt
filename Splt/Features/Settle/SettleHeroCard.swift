import SpltCore
import SwiftUI

/// The top card of the settle sheet: the people, who pays whom and the amount. It plays the ceremony.
struct SettleHeroCard: View {
    let model: SettleModel
    let ceremony: SettleCeremony

    @Environment(\.locale) private var locale

    /// While the amount rolls it moves toward what is still owed, which is zero for a full payment.
    private var shownAmount: Money? {
        guard let amount = model.amount ?? model.totals.first else { return nil }
        guard ceremony.rolled else { return amount }
        return model.remaining ?? Money.zero(currencyCode: amount.currencyCode)
    }

    var body: some View {
        VStack(spacing: 10) {
            SettleStage(
                layout: stageLayout, fraction: model.fraction, isAdjustable: canDrag,
                contraction: ceremony.contraction, ring: ceremony.ring,
                onFraction: { model.setFraction($0) }, onStep: { model.nudge(by: $0) }
            )
            caption
            if let shownAmount {
                HeroAmount(shownAmount, showsSign: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Amount \(MoneyFormatting.magnitudeString(shownAmount, locale: locale))"))
            }
            if ceremony.finished {
                Text(model.remaining == nil ? String(localized: "All square") : String(localized: "still owed"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else if !ceremony.rolled, let remaining = model.remaining {
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

    private var caption: some View {
        Text(model.headline)
            .font(.headline)
            .foregroundStyle(ceremony.finished ? .secondary : .primary)
    }

    private var stageLayout: SettleStage.Layout {
        let people = model.participants
        if people.count == 2, !model.isBatch { return .pair(payer: people[0], receiver: people[1]) }
        return .group(people)
    }

    private var canDrag: Bool {
        guard !model.isBatch, !model.isReversed, model.receipt == nil, let full = model.fullAmount else { return false }
        return full.minorUnits > model.step
    }
}
