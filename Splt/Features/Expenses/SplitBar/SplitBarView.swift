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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggingDivider: Int?
    @State private var detentCount = 0
    @State private var lastSnap: SplitBarDetent.Kind?

    private let barSpace = "splitBar"
    private let corner: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let layout = SplitBarLayout.make(weights: data.weights, scale: data.scale, width: width)
            ZStack(alignment: .topLeading) {
                segmentsRow(layout: layout)
                if data.canDrag {
                    ForEach(0..<max(data.segments.count - 1, 0), id: \.self) { divider in
                        handle(divider: divider, layout: layout)
                    }
                }
                if let divider = draggingDivider, divider + 1 < layout.visual.count {
                    callout(divider: divider, x: layout.visual[divider + 1], width: width)
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

    private func segmentsRow(layout: SplitBarLayout) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(data.segments.enumerated()), id: \.element.id) { index, segment in
                let segmentWidth = layout.widths.indices.contains(index) ? layout.widths[index] : 0
                SegmentView(
                    segment: segment, members: members, width: segmentWidth, locale: locale, scale: data.scale,
                    method: data.method, style: colorScheme == .dark ? .dark : .light
                )
                .frame(width: segmentWidth, height: height)
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

    private func spokenValue(for segment: SplitBarSegment) -> String {
        let percent = SplitBarLabels.percent(segment, scale: data.scale, locale: locale)
        guard let amount = segment.amount else { return String(localized: "\(percent)") }
        let money = MoneyFormatting.magnitudeString(amount, locale: locale)
        return String(localized: "\(money), \(percent)")
    }

    // MARK: Dividers

    private func handle(divider: Int, layout: SplitBarLayout) -> some View {
        let position = layout.visual.indices.contains(divider + 1) ? layout.visual[divider + 1] : 0
        return Capsule()
            .fill(.white)
            .frame(width: 6, height: height * 0.46)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .scaleEffect(draggingDivider == divider ? 1.2 : 1)
            .frame(width: 44, height: height)
            .contentShape(.rect)
            .position(x: position, y: height / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(barSpace))
                    .onChanged { value in
                        draggingDivider = divider
                        let fraction = layout.fraction(forX: value.location.x)
                        if let result = onDrag(divider, fraction) {
                            if let snap = result.snappedTo, lastSnap != snap { detentCount += 1 }
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

    /// The floating label above the divider being dragged: both neighbors and what they get.
    private func callout(divider: Int, x: CGFloat, width: CGFloat) -> some View {
        let pair = Array(data.segments[divider...(divider + 1)])
        return GlassPill {
            HStack(spacing: 12) {
                ForEach(pair) { segment in
                    let label = SplitBarLabels.make(method: data.method, segment: segment, scale: data.scale, wide: true, locale: locale)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(PersonPalette.color(for: segment.id, in: members))
                            .frame(width: 10, height: 10)
                        Text(firstName(of: segment.person))
                            .font(.caption.weight(.medium))
                        Text(label.primary)
                            .font(.system(.footnote, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .position(x: min(max(x, 90), max(width - 90, 90)), y: -22)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.opacity)
    }

    private func firstName(of person: Person) -> String {
        person.name.split(separator: " ").first.map(String.init) ?? person.name
    }
}

private struct SegmentView: View {
    let segment: SplitBarSegment
    let members: [PersonID]
    let width: CGFloat
    let locale: Locale
    let scale: Int64
    let method: SplitMethod
    let style: UIUserInterfaceStyle

    var body: some View {
        let fill = PersonPalette.color(for: segment.id, in: members)
        let ink = ContrastInk.ink(on: fill, style: style)
        ZStack {
            Rectangle().fill(fill)
            if width >= 26 {
                VStack(spacing: 2) {
                    initials(ink: ink)
                    if width >= 58 {
                        let label = SplitBarLabels.make(
                            method: method, segment: segment, scale: scale, wide: width >= 84, locale: locale
                        )
                        Text(label.primary)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(ink)
                            .contentTransition(.numericText())
                        if let secondary = label.secondary {
                            Text(secondary)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .foregroundStyle(ink.opacity(0.85))
                        }
                    }
                }
                .padding(.horizontal, 3)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(.systemBackground).opacity(0.5)).frame(width: 1)
        }
    }

    private func initials(ink: Color) -> some View {
        Text(AvatarStyle.initials(for: segment.person.name))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .frame(width: 24, height: 24)
            .overlay { Circle().strokeBorder(ink.opacity(0.9), lineWidth: 1.5) }
    }
}
