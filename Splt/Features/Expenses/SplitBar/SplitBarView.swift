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

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 56
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggingDivider: Int?
    @State private var detentCount = 0
    @State private var lastSnap: SplitBarDetent.Kind?
    /// The callout's measured width, so it can be kept inside the bar at either end.
    @State private var calloutWidth: CGFloat = 180

    private let barSpace = "splitBar"
    private let corner = Depth.controlRadius

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let layout = SplitBarLayout.make(weights: data.weights, scale: data.scale, width: width)
            let _ = PersonColorRevision.shared.value
            let palette = PersonPalette.colors(for: members)
            ZStack(alignment: .topLeading) {
                segmentsRow(layout: layout, palette: palette)
                if data.canDrag {
                    ForEach(0..<max(data.segments.count - 1, 0), id: \.self) { divider in
                        handle(divider: divider, layout: layout)
                    }
                    handleGrip(layout: layout)
                }
                if let divider = draggingDivider, divider + 1 < layout.visual.count {
                    callout(divider: divider, x: layout.visual[divider + 1], width: width, palette: palette)
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

    private func fill(for person: PersonID, in palette: [PersonID: Color]) -> Color {
        palette[person] ?? PersonPalette.color(for: person)
    }

    private func segmentsRow(layout: SplitBarLayout, palette: [PersonID: Color]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(data.segments.enumerated()), id: \.element.id) { index, segment in
                let segmentWidth = layout.widths.indices.contains(index) ? layout.widths[index] : 0
                SegmentView(
                    segment: segment, fill: fill(for: segment.id, in: palette), width: segmentWidth, locale: locale, scale: data.scale,
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
            .fill(Ink.paper)
            .frame(width: 4, height: height * 0.5)
            .scaleEffect(draggingDivider == divider ? 1.2 : 1)
            .motion(Motion.quick, value: draggingDivider)
            .frame(width: 44, height: height)
            .position(x: position, y: height / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// One touch area for every divider: 44pt around each, and a touch moves the divider nearest to
    /// where it landed. Separate areas per divider overlap where a segment is narrow, and then the
    /// later divider would always win.
    private func handleGrip(layout: SplitBarLayout) -> some View {
        let positions = Array(layout.visual.dropFirst().dropLast())
        return Color.clear
            .contentShape(DividerZones(positions: positions, reach: 22))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(barSpace))
                    .onChanged { value in
                        guard let divider = draggingDivider
                            ?? SplitBarLayout.nearest(to: value.startLocation.x, in: positions) else { return }
                        if draggingDivider != divider {
                            Motion.perform(Motion.quick) { draggingDivider = divider }
                        }
                        let fraction = layout.fraction(forX: value.location.x)
                        if let result = onDrag(divider, fraction) {
                            if let snap = result.snappedTo, lastSnap != snap { detentCount += 1 }
                            lastSnap = result.snappedTo
                        }
                    }
                    .onEnded { _ in
                        Motion.perform(Motion.quick) { draggingDivider = nil }
                        lastSnap = nil
                    }
            )
            .accessibilityHidden(true)
    }

    /// The floating label above the divider being dragged: both neighbors and what they get.
    private func callout(divider: Int, x: CGFloat, width: CGFloat, palette: [PersonID: Color]) -> some View {
        let pair = Array(data.segments[divider...(divider + 1)])
        return Group {
            HStack(spacing: 12) {
                ForEach(pair) { segment in
                    let label = SplitBarLabels.make(method: data.method, segment: segment, scale: data.scale, wide: true, locale: locale)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(fill(for: segment.id, in: palette))
                            .frame(width: 10, height: 10)
                        Text(firstName(of: segment.person))
                            .font(.caption)
                        Text(label.primary)
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Ink.sheet, in: Capsule())
            .overlay { Capsule().strokeBorder(Ink.hairline) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { calloutWidth = $0 }
        .position(x: calloutX(x, barWidth: width), y: -22)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .motionTransition(.opacity)
    }

    /// Centers the callout on the divider, but never lets it hang past either end of the bar.
    private func calloutX(_ x: CGFloat, barWidth: CGFloat) -> CGFloat {
        let half = calloutWidth / 2
        guard barWidth > calloutWidth else { return barWidth / 2 }
        return min(max(x, half), barWidth - half)
    }

    private func firstName(of person: Person) -> String {
        person.name.split(separator: " ").first.map(String.init) ?? person.name
    }
}

/// The touch areas of the dividers: a band `reach` points either side of each.
private struct DividerZones: Shape {
    var positions: [CGFloat]
    var reach: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in positions {
            path.addRect(CGRect(x: x - reach, y: rect.minY, width: reach * 2, height: rect.height))
        }
        return path
    }
}

private struct SegmentView: View {
    let segment: SplitBarSegment
    let fill: Color
    let width: CGFloat
    let locale: Locale
    let scale: Int64
    let method: SplitMethod
    let style: UIUserInterfaceStyle

    var body: some View {
        let ink = ContrastInk.ink(on: fill, style: style)
        ZStack {
            Rectangle().fill(fill)
            if width >= 26 {
                VStack(spacing: 1) {
                    Text(width >= 58 ? firstName : AvatarStyle.initials(for: segment.person.name))
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if width >= 58 {
                        let label = SplitBarLabels.make(
                            method: method, segment: segment, scale: scale, wide: false, locale: locale
                        )
                        Text(label.primary)
                            .font(.caption2.monospacedDigit())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 3)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Ink.paper).frame(width: 1)
        }
    }

    private var firstName: String {
        segment.person.name.split(separator: " ").first.map(String.init) ?? segment.person.name
    }
}
