import SpltCore
import SwiftUI

/// Who is in the settle moment, with the color they carry through the app.
struct SettleParticipant: Identifiable, Equatable {
    var id: PersonID
    var name: String
    var color: Color
}

/// The two people of a payment facing each other, with an arc between them in their blended colors.
/// Dragging the knob along the arc chooses how much of the debt is paid. For a whole group the
/// people stand in a row and only the ring closes around them.
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

    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 64
    @State private var lastDetent: Int?

    private let baseDiameter: CGFloat = 64
    private let inset: CGFloat = 14

    private var diameter: CGFloat { AvatarView.diameter(scaled: scaledDiameter, base: baseDiameter) }
    private var peak: CGFloat { diameter * 0.75 }
    private var height: CGFloat { diameter + peak + 28 }
    private var rowY: CGFloat { height - diameter / 2 - 14 }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                switch layout {
                case .pair(let payer, let receiver):
                    pair(payer, receiver, width: width)
                case .group(let people):
                    group(people, width: width)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .frame(height: height)
    }

    // MARK: Pair

    private func pair(_ payer: SettleParticipant, _ receiver: SettleParticipant, width: CGFloat) -> some View {
        let start = CGPoint(x: inset + diameter / 2, y: rowY)
        let end = CGPoint(x: width - inset - diameter / 2, y: rowY)
        let geometry = SettleArcGeometry(start: start, end: end, radius: diameter / 2 + 6, peak: peak)
        let flow = LinearGradient(colors: [payer.color, receiver.color], startPoint: .leading, endPoint: .trailing)
        let isContracting = contraction > 0

        return ZStack(alignment: .topLeading) {
            ringShape(width: width, flow: flow)
            SettleArcShape(geometry: geometry, contraction: contraction)
                .stroke(Color(.tertiarySystemFill), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            SettleArcShape(geometry: geometry, contraction: contraction)
                .trim(from: 0, to: max(fraction, 0.001))
                .stroke(flow, style: StrokeStyle(lineWidth: 8 * (1 - 0.5 * contraction), lineCap: .round))
            Circle()
                .fill(flow)
                .frame(width: 14, height: 14)
                .position(geometry.point(at: 0.5, contraction: 1))
                .scaleEffect(isContracting ? 1 : 0.2)
                .opacity(isContracting ? 1 : 0)
            if isAdjustable, contraction == 0 {
                knob(at: geometry.point(at: fraction, contraction: 0))
            }
            avatar(payer, at: start)
            avatar(receiver, at: end)
        }
        .contentShape(Rectangle())
        .gesture(isAdjustable && contraction == 0 ? drag(geometry) : nil)
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
            .fill(.background)
            .frame(width: 26, height: 26)
            .overlay { Circle().strokeBorder(Color(.separator), lineWidth: 1) }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .padding(9)
            .contentShape(Circle())
            .position(point)
    }

    private func drag(_ geometry: SettleArcGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let span = max(geometry.end.x - geometry.start.x, 1)
                let value = Double((value.location.x - geometry.start.x) / span)
                let share = min(max(value, 0), 1)
                onFraction(share)
                let detent = Int((share * 4).rounded())
                if detent != lastDetent {
                    lastDetent = detent
                    Haptics.play(.detent)
                }
            }
            .onEnded { _ in lastDetent = nil }
    }

    // MARK: Group

    private func group(_ people: [SettleParticipant], width: CGFloat) -> some View {
        let shown = Array(people.prefix(5))
        let gap = diameter * 0.7
        let total = diameter + gap * CGFloat(max(shown.count - 1, 0))
        let left = (width - total) / 2 + diameter / 2
        let colors = shown.map(\.color)
        let flow = LinearGradient(colors: colors.isEmpty ? [.accentColor] : colors, startPoint: .leading, endPoint: .trailing)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: (diameter + 16) / 2, style: .continuous)
                .trim(from: 0, to: ring)
                .stroke(flow, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: total + 16, height: diameter + 16)
                .position(x: width / 2, y: height / 2)
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, person in
                avatar(person, at: CGPoint(x: left + gap * CGFloat(index), y: height / 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ListFormatter.localizedString(byJoining: people.map(\.name))))
    }

    // MARK: Pieces

    private func ringShape(width: CGFloat, flow: LinearGradient) -> some View {
        Capsule()
            .trim(from: 0, to: ring)
            .stroke(flow, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .frame(width: width - inset * 2 + 16, height: diameter + 16)
            .position(x: width / 2, y: rowY)
    }

    private func avatar(_ person: SettleParticipant, at point: CGPoint) -> some View {
        AvatarView(name: person.name, id: person.id, members: [person.id], size: baseDiameter)
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
