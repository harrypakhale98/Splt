import SpltCore
import SwiftUI

/// The Split Bar: one segment per person in their color, dividers you drag to change who pays
/// what. Dividers click into place at the equal split, whole amounts and round percentages.
struct SplitBarView: View {
    let data: SplitBarData
    let members: [PersonID]
    let currentPerson: PersonID?
    let stepHint: String
    var onDrag: (Int, Double) -> SplitBarDrag?
    var onStep: (PersonID, Bool) -> Void
    var onTap: (PersonID) -> Void

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 76
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggingDivider: Int?
    @State private var detentCount = 0
    @State private var lastSnap: SplitBarDetent.Kind?

    private let barSpace = "splitBar"
    private let corner: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                segmentsRow(width: width)
                if data.canDrag {
                    ForEach(0..<max(data.segments.count - 1, 0), id: \.self) { divider in
                        handle(divider: divider, width: width)
                    }
                }
            }
            .coordinateSpace(name: barSpace)
        }
        .frame(height: height)
        .haptics(.detent, trigger: detentCount)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Split bar")
    }

    // MARK: Segments

    private func segmentsRow(width: CGFloat) -> some View {
        let widths = segmentWidths(total: width)
        return HStack(spacing: 0) {
            ForEach(Array(data.segments.enumerated()), id: \.element.id) { index, segment in
                SegmentView(
                    segment: segment, members: members, width: widths[index], locale: locale,
                    isYou: segment.id == currentPerson, fraction: fraction(of: segment),
                    method: data.method
                )
                .frame(width: widths[index], height: height)
                .contentShape(.rect)
                .onTapGesture { onTap(segment.id) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(segment.id == currentPerson ? String(localized: "You") : segment.person.name)
                .accessibilityValue(spokenValue(for: segment))
                .accessibilityHint(data.canDrag ? String(localized: "Swipe up or down to change. \(stepHint) at a time.") : "")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: onStep(segment.id, true)
                    case .decrement: onStep(segment.id, false)
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: Text("Fine tune")) { onTap(segment.id) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .animation(draggingDivider == nil && !reduceMotion ? Motion.snappy : nil, value: data.weights)
    }

    private func segmentWidths(total: CGFloat) -> [CGFloat] {
        let usable = total.isFinite ? max(total, 0) : 0
        guard data.scale > 0 else { return data.segments.map { _ in usable / CGFloat(max(data.segments.count, 1)) } }
        return data.segments.map { max(usable * CGFloat($0.weight) / CGFloat(data.scale), 0) }
    }

    private func fraction(of segment: SplitBarSegment) -> Double {
        data.scale > 0 ? Double(segment.weight) / Double(data.scale) : 0
    }

    private func spokenValue(for segment: SplitBarSegment) -> String {
        let percent = (fraction(of: segment) * 100).formatted(.number.precision(.fractionLength(0)))
        guard let amount = segment.amount else { return String(localized: "\(percent) percent") }
        let money = MoneyFormatting.magnitudeString(amount, locale: locale)
        return String(localized: "\(money), \(percent) percent")
    }

    // MARK: Dividers

    private func handle(divider: Int, width: CGFloat) -> some View {
        let position = max(width, 0) * CGFloat(data.weights[...divider].reduce(0, +)) / CGFloat(max(data.scale, 1))
        return Capsule()
            .fill(.white)
            .frame(width: 6, height: height * 0.46)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .scaleEffect(draggingDivider == divider ? 1.15 : 1)
            .frame(width: 44, height: height)
            .contentShape(.rect)
            .position(x: position, y: height / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(barSpace))
                    .onChanged { value in
                        draggingDivider = divider
                        let fraction = Double(value.location.x / max(width, 1))
                        if let result = onDrag(divider, fraction) {
                            if let snap = result.snappedTo, snap != lastSnap || result.didChange {
                                if lastSnap != snap { detentCount += 1 }
                            }
                            lastSnap = result.snappedTo
                        }
                    }
                    .onEnded { _ in
                        draggingDivider = nil
                        lastSnap = nil
                    }
            )
            .accessibilityHidden(true)
    }
}

private struct SegmentView: View {
    let segment: SplitBarSegment
    let members: [PersonID]
    let width: CGFloat
    let locale: Locale
    let isYou: Bool
    let fraction: Double
    let method: SplitMethod

    var body: some View {
        ZStack {
            Rectangle().fill(PersonPalette.color(for: segment.id, in: members))
            if width >= 36 {
                VStack(spacing: 2) {
                    AvatarView(name: segment.person.name, id: segment.id, members: members, size: 24)
                        .overlay { Circle().strokeBorder(PersonPalette.onColor.opacity(0.9), lineWidth: 1.5) }
                    if width >= 58 {
                        Text(label)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(PersonPalette.onColor)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(.systemBackground).opacity(0.5)).frame(width: 1)
        }
    }

    private var label: String {
        if let amount = segment.amount { return MoneyFormatting.magnitudeString(amount, locale: locale) }
        return (fraction * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }
}
