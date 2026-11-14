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
    /// Fixed hues for people the color book has never seen, such as the welcome tour's sample split.
    var hues: [PersonID: Int]?
    /// False where tapping a person opens nothing, so VoiceOver offers no Fine tune action.
    var offersFineTune = true

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 56
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggingDivider: Int?
    /// True while a finger is on the bar. It clears itself when a drag is cancelled, which `onEnded` never hears about.
    @GestureState private var isDragging = false
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
            let palette = hues?.mapValues { PersonPalette.color(at: $0) } ?? PersonPalette.colors(for: members)
            ZStack(alignment: .topLeading) {
                segmentsRow(layout: layout, palette: palette)
                if data.canDrag {
                    ForEach(0..<max(data.segments.count - 1, 0), id: \.self) { divider in
                        handle(divider: divider, layout: layout)
                    }
                    handleGrip(layout: layout, width: width)
                }
                if let divider = draggingDivider, let pair = data.neighbors(of: divider), layout.visual.indices.contains(divider + 1) {
                    callout(pair: pair, x: layout.visual[divider + 1], width: width, palette: palette)
                }
            }
            .coordinateSpace(name: barSpace)
        }
        .frame(height: height)
        .onChange(of: isDragging) { _, dragging in
            guard !dragging else { return }
            Motion.perform(Motion.quick) { draggingDivider = nil }
            lastSnap = nil
        }
        // the divider that was held may be gone, or stand between other people now
        .onChange(of: data.segments.count) { draggingDivider = nil }
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
                    method: data.method, style: colorScheme == .dark ? .dark : .light,
                    isCurrentPerson: segment.id == currentPerson
                )
                .frame(width: segmentWidth, height: height)
                .contentShape(.rect)
                .onTapGesture { onTap(segment.id) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(segment.id == currentPerson ? String(localized: "You") : segment.person.name)
                .accessibilityValue(spokenValue(for: segment))
                .accessibilityHint(data.canDrag ? String(localized: "Swipe up or down to change. \(stepHint) at a time.") : "")
                .adjustable(when: data.canDrag) { increase in onStep(segment.id, increase) }
                .accessibilityActions {
                    if offersFineTune { Button("Fine tune") { onTap(segment.id) } }
                }
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
    private func handleGrip(layout: SplitBarLayout, width: CGFloat) -> some View {
        // a touch's x and a shape's path run from the left even where the bar is mirrored
        let mirrored = layoutDirection == .rightToLeft
        let positions = layout.visual.dropFirst().dropLast().map { mirrored ? width - $0 : $0 }
        return Color.clear
            .contentShape(DividerZones(positions: positions, reach: 22))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(barSpace))
                    .updating($isDragging) { _, dragging, _ in dragging = true }
                    .onChanged { value in
                        guard let divider = draggingDivider
                            ?? SplitBarLayout.nearest(to: value.startLocation.x, in: positions),
                            data.neighbors(of: divider) != nil else { return }
                        if draggingDivider != divider {
                            Motion.perform(Motion.quick) { draggingDivider = divider }
                        }
                        let fraction = layout.fraction(forX: mirrored ? width - value.location.x : value.location.x)
                        if let result = onDrag(divider, fraction) {
                            if let snap = result.snappedTo, lastSnap != snap { detentCount += 1 }
                            lastSnap = result.snappedTo
                        }
                    }
            )
            .accessibilityHidden(true)
    }

    /// The floating label above the divider being dragged: both neighbors and what they get.
    private func callout(pair: [SplitBarSegment], x: CGFloat, width: CGFloat, palette: [PersonID: Color]) -> some View {
        Group {
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

    /// The short name on the bar. You are "You" here as on the chips above it.
    private func firstName(of person: Person) -> String {
        if person.id == currentPerson { return String(localized: "You") }
        return person.name.split(separator: " ").first.map(String.init) ?? person.name
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

extension View {
    /// VoiceOver announces any element with an adjustable action as adjustable, so only add it when swiping changes something.
    @ViewBuilder
    func adjustable(when isAdjustable: Bool, _ step: @escaping (_ increase: Bool) -> Void) -> some View {
        if isAdjustable {
            accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(true)
                case .decrement: step(false)
                @unknown default: break
                }
            }
        } else {
            self
        }
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
    let isCurrentPerson: Bool

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
                            // every label grows and shrinks with the weight, so it gives the roll its direction
                            .contentTransition(.numericText(value: Double(segment.amount?.minorUnits ?? segment.weight)))
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
        if isCurrentPerson { return String(localized: "You") }
        return segment.person.name.split(separator: " ").first.map(String.init) ?? segment.person.name
    }
}
