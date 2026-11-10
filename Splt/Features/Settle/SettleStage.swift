import SpltCore
import SwiftUI

/// Who is in the settle moment, with the color they carry through the app.
struct SettleParticipant: Identifiable, Equatable {
    var id: PersonID
    var name: String
    var color: Color
    /// The name the person is stored under, for their initials. `name` may read "You".
    var avatarName: String?
}

/// The two people of a payment facing each other, with an arc between them in their blended colors.
/// Dragging the knob along the arc chooses how much of the debt is paid. A whole group has no
/// pair to join, so it shows the strip of everyone's colors.
struct SettleStage: View {
    enum Layout {
        /// Payer on the left, receiver on the right.
        case pair(payer: SettleParticipant, receiver: SettleParticipant)
        case group([SettleParticipant])
    }

    let layout: Layout
    /// The share of the debt being paid, 0 to 1.
    var fraction: Double
    /// Whether the knob can be dragged.
    var isAdjustable: Bool
    /// 0 for the full arc, 1 for a single point.
    var contraction: CGFloat
    /// How much of the ring around the people is drawn.
    var ring: CGFloat
    var onFraction: (Double) -> Void
    var onStep: (Int) -> Void

    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 40
    /// Set by the first few points of a drag. Only a sideways drag moves the knob, so scrolling the sheet doesn't.
    /// Resets by itself when the drag ends or the scroll view takes it over.
    @GestureState private var track = DragTrack()

    private let baseDiameter: CGFloat = 40
    private let inset: CGFloat = 14
    private let knobSize: CGFloat = 26

    private var diameter: CGFloat { AvatarView.diameter(scaled: scaledDiameter, base: baseDiameter) }
    private var peak: CGFloat { diameter * 0.75 }
    private var height: CGFloat { diameter + peak + 28 }
    private var rowY: CGFloat { height - diameter / 2 - 14 }

    var body: some View {
        switch layout {
        case .pair(let payer, let receiver):
            GeometryReader { proxy in
                pair(payer, receiver, width: proxy.size.width)
                    .frame(width: proxy.size.width, height: height, alignment: .topLeading)
            }
            .frame(height: height)
        case .group(let people):
            group(people)
        }
    }

    // MARK: Pair

    private func pair(_ payer: SettleParticipant, _ receiver: SettleParticipant, width: CGFloat) -> some View {
        let start = CGPoint(x: inset + diameter / 2, y: rowY)
        let end = CGPoint(x: width - inset - diameter / 2, y: rowY)
        // the arc ends 6pt off each disc; the knob stops further in, leaving an 8pt gap, so it sits whole on
        // the line with a small gap before the person instead of tucking under their disc
        let geometry = SettleArcGeometry(
            start: start, end: end, radius: diameter / 2 + 6, peak: peak, knobInset: knobSize / 2 + 2
        )
        let isContracting = contraction > 0

        return ZStack(alignment: .topLeading) {
            ringShape(width: width)
            // the track ends where the knob stops, so nothing pokes out past it toward the person
            SettleArcShape(geometry: geometry, contraction: contraction)
                .trim(from: 0, to: contraction > 0 ? 1 : geometry.knobT(for: 1))
                .stroke(Ink.hairline, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            SettleArcShape(geometry: geometry, contraction: contraction)
                .trim(from: 0, to: contraction > 0 ? max(fraction, 0.001) : (fraction > 0 ? geometry.knobT(for: fraction) : 0))
                .stroke(Ink.text, style: StrokeStyle(lineWidth: 4 * (1 - 0.5 * contraction), lineCap: .round))
            Circle()
                .fill(Ink.text)
                .frame(width: 12, height: 12)
                .position(geometry.point(at: 0.5, contraction: 1))
                .scaleEffect(isContracting ? 1 : 0.2)
                .opacity(isContracting ? 1 : 0)
            if isAdjustable, contraction == 0 {
                knob(at: geometry.point(at: geometry.knobT(for: fraction), contraction: 0))
            }
            avatar(payer, at: start)
            avatar(receiver, at: end)
        }
        .contentShape(Rectangle())
        // Simultaneous, so a vertical drag that starts here still scrolls the sheet.
        .simultaneousGesture(isAdjustable && contraction == 0 ? drag(geometry) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(payer.name) pays \(receiver.name)"))
        .accessibilityValue(isAdjustable ? Text("\(Int((fraction * 100).rounded())) percent of what is owed") : Text(""))
        .accessibilityAdjustableAction { direction in
            guard isAdjustable else { return }
            switch direction {
            case .increment: onStep(1)
            case .decrement: onStep(-1)
            @unknown default: break
            }
        }
    }

    private func knob(at point: CGPoint) -> some View {
        Circle()
            .fill(Ink.paper)
            .frame(width: knobSize, height: knobSize)
            .overlay { Circle().strokeBorder(Ink.text, lineWidth: 1.5) }
            .padding(9)
            .contentShape(Circle())
            .position(point)
    }

    private func drag(_ geometry: SettleArcGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($track) { value, track, _ in
                let moved = hypot(value.translation.width, value.translation.height)
                if track.isSideways == nil {
                    // wait for a real movement before deciding, so a vertical scroll never moves the amount
                    guard moved >= 6 else { return }
                    track.isSideways = abs(value.translation.width) > abs(value.translation.height)
                }
                guard track.isSideways == true else { return }
                let detent = apply(value.location, geometry)
                if detent != track.detent {
                    track.detent = detent
                    Haptics.play(.detent)
                }
            }
            .onEnded { value in
                // a tap jumps the knob to where the finger landed
                if hypot(value.translation.width, value.translation.height) < 6 {
                    _ = apply(value.location, geometry)
                    Haptics.play(.detent)
                }
            }
    }

    /// Sets the amount from a point on the stage and returns the nearest quarter, for the detent haptic.
    private func apply(_ location: CGPoint, _ geometry: SettleArcGeometry) -> Int {
        let share = geometry.fraction(atX: location.x)
        onFraction(share)
        return Int((share * 4).rounded())
    }

    // MARK: Group

    private func group(_ people: [SettleParticipant]) -> some View {
        ShareStrip(colors: people.map(\.color))
            .padding(.vertical, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ListFormatter.localizedString(byJoining: people.map(\.name))))
    }

    // MARK: Pieces

    private func ringShape(width: CGFloat) -> some View {
        Capsule()
            .trim(from: 0, to: ring)
            .stroke(Ink.text, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: width - inset * 2 + 16, height: diameter + 16)
            .position(x: width / 2, y: rowY)
    }

    private func avatar(_ person: SettleParticipant, at point: CGPoint) -> some View {
        AvatarView(name: person.avatarName ?? person.name, id: person.id, size: baseDiameter)
            .position(point)
            .motion(.smooth, value: point)
    }
}

/// Where the arc runs: a gentle curve above the line between the two avatars.
struct SettleArcGeometry {
    var start: CGPoint
    var end: CGPoint
    /// How far the ends stay from the avatar centers, so the arc starts at their edges.
    var radius: CGFloat
    var peak: CGFloat
    /// How far the knob's center stays in from each end of the arc.
    var knobInset: CGFloat = 0

    private var span: CGFloat { max(end.x - start.x - 2 * radius, 1) }
    private var knobEdge: Double { min(Double(knobInset / span), 0.45) }

    /// Where along the arc the knob sits for a share of the debt, kept clear of both ends.
    func knobT(for fraction: Double) -> Double {
        knobEdge + min(max(fraction, 0), 1) * (1 - 2 * knobEdge)
    }

    /// The share of the debt for a finger at `x`: the inverse of `knobT`.
    func fraction(atX x: CGFloat) -> Double {
        let t = Double((x - start.x - radius) / span)
        return min(max((t - knobEdge) / (1 - 2 * knobEdge), 0), 1)
    }

    private var middleX: CGFloat { (start.x + end.x) / 2 }

    /// The curve at a given contraction: ends slide to the middle and the bow flattens.
    func controlPoints(contraction: CGFloat) -> (from: CGPoint, control: CGPoint, to: CGPoint) {
        let from = CGPoint(x: start.x + radius, y: start.y)
        let to = CGPoint(x: end.x - radius, y: end.y)
        let c = min(max(contraction, 0), 1)
        let slidFrom = CGPoint(x: from.x + (middleX - from.x) * c, y: from.y)
        let slidTo = CGPoint(x: to.x + (middleX - to.x) * c, y: to.y)
        let control = CGPoint(x: middleX, y: start.y - peak * 2 * (1 - c))
        return (slidFrom, control, slidTo)
    }

    /// The point a share `t` of the way along the arc. x is linear in t because the control sits in the middle.
    func point(at t: Double, contraction: CGFloat) -> CGPoint {
        let curve = controlPoints(contraction: contraction)
        let t = CGFloat(min(max(t, 0), 1))
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * curve.from.x + 2 * inverse * t * curve.control.x + t * t * curve.to.x,
            y: inverse * inverse * curve.from.y + 2 * inverse * t * curve.control.y + t * t * curve.to.y
        )
    }
}

struct SettleArcShape: Shape {
    var geometry: SettleArcGeometry
    var contraction: CGFloat

    var animatableData: CGFloat {
        get { contraction }
        set { contraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let curve = geometry.controlPoints(contraction: contraction)
        var path = Path()
        path.move(to: curve.from)
        path.addQuadCurve(to: curve.to, control: curve.control)
        return path
    }
}

private struct DragTrack {
    var isSideways: Bool?
    var detent: Int?
}
