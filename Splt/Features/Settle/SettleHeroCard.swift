import SpltCore
import SwiftUI

/// The top of the settle sheet, on paper: the people joined by an arc, who pays whom and one large amount. It plays the ceremony.
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
            if !ceremony.rolled, let otherTotals {
                Text("Also \(otherTotals)")
                    .font(Typeface.figure)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }
            if ceremony.finished {
                Text(model.remaining == nil ? String(localized: "Settled up") : String(localized: "still owed"))
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                    .motionTransition(.opacity)
            } else if !ceremony.rolled, let remaining = model.remaining {
                Text("\(MoneyFormatting.magnitudeString(remaining, locale: locale)) will still be owed")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
    }

    /// The other currencies of a whole group, which the one big figure can't hold.
    private var otherTotals: String? {
        guard model.amount == nil, model.totals.count > 1 else { return nil }
        return ListFormatter.localizedString(
            byJoining: model.totals.dropFirst().map { MoneyFormatting.magnitudeString($0, locale: locale) }
        )
    }

    private var caption: some View {
        Text(model.headline)
            .font(.headline)
            .foregroundStyle(ceremony.finished ? Ink.secondary : Ink.text)
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
