import SpltCore
import SwiftUI

/// The bar as a plain list: every person, their amount and percentage, and buttons to change it.
/// The alternative for VoiceOver and for the largest text sizes.
struct SplitShareList: View {
    let data: SplitBarData
    let members: [PersonID]
    let currentPerson: PersonID?
    var onStep: (PersonID, Bool) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ForEach(data.segments) { segment in
                row(segment)
                if segment.id != data.segments.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func row(_ segment: SplitBarSegment) -> some View {
        let name = segment.id == currentPerson ? String(localized: "You") : segment.person.name
        let percent = data.scale > 0 ? Double(segment.weight) / Double(data.scale) * 100 : 0
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                identity(segment, name: name)
                Spacer(minLength: 8)
                amounts(segment, percent: percent)
                if data.canDrag { steppers(segment, name: name) }
            }
            VStack(alignment: .leading, spacing: 8) {
                identity(segment, name: name)
                amounts(segment, percent: percent)
                if data.canDrag { steppers(segment, name: name) }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(spoken(segment, percent: percent))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep(segment.id, true)
            case .decrement: onStep(segment.id, false)
            @unknown default: break
            }
        }
    }

    private func identity(_ segment: SplitBarSegment, name: String) -> some View {
        HStack(spacing: 10) {
            AvatarView(name: segment.person.name, id: segment.id, members: members, size: 32)
            Text(name).font(.body.weight(.medium))
        }
    }

    private func amounts(_ segment: SplitBarSegment, percent: Double) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let amount = segment.amount {
                MoneyLabel(money: amount).font(.system(.body, design: .rounded, weight: .semibold))
            }
            Text(percent.formatted(.number.precision(.fractionLength(0))) + "%")
                .font(.caption)
                .foregroundStyle(.legible)
                .monospacedDigit()
        }
    }

    private func steppers(_ segment: SplitBarSegment, name: String) -> some View {
        HStack(spacing: 4) {
            Button { onStep(segment.id, false) } label: { Image(systemName: "minus") }
                .accessibilityLabel("Less for \(name)")
            Button { onStep(segment.id, true) } label: { Image(systemName: "plus") }
                .accessibilityLabel("More for \(name)")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
    }

    private func spoken(_ segment: SplitBarSegment, percent: Double) -> String {
        let percentText = percent.formatted(.number.precision(.fractionLength(0)))
        guard let amount = segment.amount else { return String(localized: "\(percentText) percent") }
        return String(localized: "\(MoneyFormatting.magnitudeString(amount, locale: locale)), \(percentText) percent")
    }
}
