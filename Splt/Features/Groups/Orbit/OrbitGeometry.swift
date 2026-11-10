import CoreGraphics
import Foundation

/// Where the people sit on the ring and how big they are, for a given size and head count.
/// Pure geometry: nothing here draws.
struct OrbitLayout: Equatable {
    enum LabelStyle: Equatable {
        /// A first name under each person.
        case name
        /// A short first name in small type.
        case compact
        /// No labels. A person's name shows when they are focused.
        case hidden
    }

    let size: CGSize
    let count: Int
    let center: CGPoint
    let ringRadius: CGFloat
    let nodeRadius: CGFloat
    let labelStyle: LabelStyle
    /// Angle of the first person in radians. Zero points right and angles grow clockwise.
    let startAngle: Double
    let positions: [CGPoint]

    init(size: CGSize, count: Int) {
        self.size = size
        self.count = max(count, 0)
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        let side = max(min(size.width, size.height), 1)

        let style: LabelStyle = count <= 6 ? .name : (count <= 9 ? .compact : .hidden)
        labelStyle = style
        let labelRoom: CGFloat = style == .hidden ? 0 : (style == .name ? 26 : 18)

        var node = side * (count <= 4 ? 0.07 : count <= 6 ? 0.063 : count <= 9 ? 0.054 : 0.046)
        let margin: CGFloat = 8
        let ring = max(side / 2 - node - labelRoom - margin, 1)
        if count >= 3 {
            // neighbors must never touch
            node = min(node, ring * CGFloat(sin(Double.pi / Double(count))) / 1.15)
        }
        nodeRadius = max(node, 8)
        ringRadius = max(side / 2 - nodeRadius - labelRoom - margin, 1)
        startAngle = count == 2 ? Double.pi : -Double.pi / 2

        var points: [CGPoint] = []
        for index in 0..<self.count {
            let angle = startAngle + 2 * Double.pi * Double(index) / Double(max(count, 1))
            points.append(CGPoint(
                x: center.x + ringRadius * CGFloat(cos(angle)),
                y: center.y + ringRadius * CGFloat(sin(angle))
            ))
        }
        positions = points
    }

    /// The direction pointing away from the center at one person, for placing their label.
    func outward(_ index: Int) -> CGVector {
        guard positions.indices.contains(index) else { return CGVector(dx: 0, dy: 1) }
        let angle = startAngle + 2 * Double.pi * Double(index) / Double(max(count, 1))
        return CGVector(dx: CGFloat(cos(angle)), dy: CGFloat(sin(angle)))
    }

    /// Where the name label of a person is centered: under them, or above for the top of the ring.
    func labelPosition(_ index: Int) -> CGPoint {
        guard positions.indices.contains(index) else { return center }
        let direction: CGFloat = outward(index).dy < -0.3 ? -1 : 1
        return CGPoint(x: positions[index].x, y: positions[index].y + direction * (nodeRadius + 11))
    }

    /// The widest a name label may be before it truncates: it stays on the canvas and clear of the
    /// labels of the people on either side.
    func labelMaxWidth(_ index: Int) -> CGFloat {
        guard positions.indices.contains(index) else { return 0 }
        let x = positions[index].x
        var cap = 2 * min(x, size.width - x) - 4
        if count >= 3 {
            let neighbor = 2 * ringRadius * CGFloat(sin(Double.pi / Double(count)))
            cap = min(cap, neighbor - 6)
        }
        return max(cap, nodeRadius * 2)
    }

    /// The widest an arc may be.
    var maxArcWidth: CGFloat { min(nodeRadius * 0.3, 5) }
    var minArcWidth: CGFloat { 1.5 }

    /// Arc width for an amount, in proportion to the largest amount on the ring.
    func arcWidth(amount: Int64, largest: Int64) -> CGFloat {
        guard largest > 0, amount > 0 else { return minArcWidth }
        let share = min(CGFloat(Double(amount) / Double(largest)), 1)
        return minArcWidth + (maxArcWidth - minArcWidth) * share
    }

    /// The curve from one person to another, starting and ending just outside their avatars.
    func arc(from source: Int, to target: Int, width: CGFloat) -> ArcGeometry? {
        guard positions.indices.contains(source), positions.indices.contains(target), source != target else { return nil }
        let a = positions[source]
        let b = positions[target]
        let control = controlPoint(a, b)
        let inset = nodeRadius + 3
        return ArcGeometry(
            start: a.moved(toward: control, by: inset),
            control: control,
            end: b.moved(toward: control, by: inset),
            width: width
        )
    }

    /// The radius of the empty disc in the middle, where the amount sits.
    var centerRadius: CGFloat { ringRadius * 0.52 }

    /// Arcs bow toward the middle like a chord diagram but never into the disc where the amount sits.
    /// A pair whose straight line would pass too close arches out to the side instead.
    private func controlPoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let inward = CGVector(dx: center.x - mid.x, dy: center.y - mid.y)
        let distance = hypot(inward.dx, inward.dy)
        let clear = ringRadius * 0.68
        if distance < clear {
            var direction = CGVector(dx: -inward.dx / max(distance, 0.0001), dy: -inward.dy / max(distance, 0.0001))
            if distance < ringRadius * 0.02 {
                // exactly opposite: arch up, or to the right of the way from a to b when that is vertical
                let chord = CGVector(dx: b.x - a.x, dy: b.y - a.y)
                let length = max(hypot(chord.dx, chord.dy), 1)
                direction = CGVector(dx: -chord.dy / length, dy: chord.dx / length)
                if direction.dy > 0 { direction = CGVector(dx: -direction.dx, dy: -direction.dy) }
            }
            let reach = 2 * (ringRadius * 0.76 - distance)
            return CGPoint(x: mid.x + direction.dx * reach, y: mid.y + direction.dy * reach)
        }
        let pull = min(0.7, 2 * (1 - clear / distance))
        return CGPoint(x: mid.x + inward.dx * pull, y: mid.y + inward.dy * pull)
    }
}

/// A quadratic curve with a width: one transfer of money drawn between two people.
struct ArcGeometry: Equatable {
    var start: CGPoint
    var control: CGPoint
    var end: CGPoint
    var width: CGFloat

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    /// The direction of travel at `t`, as a unit vector.
    func tangent(at t: CGFloat) -> CGVector {
        let dx = 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x)
        let dy = 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
        let length = max(hypot(dx, dy), 0.0001)
        return CGVector(dx: dx / length, dy: dy / length)
    }

    func polyline(samples: Int = 24) -> [CGPoint] {
        let count = max(samples, 2)
        return (0...count).map { point(at: CGFloat($0) / CGFloat(count)) }
    }

    /// The two edges of a ribbon that follows the curve and narrows toward the end, so it reads as
    /// money flowing from the start to the end.
    func ribbon(samples: Int = 24, taper: CGFloat = 0.55) -> (left: [CGPoint], right: [CGPoint]) {
        let count = max(samples, 2)
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for index in 0...count {
            let t = CGFloat(index) / CGFloat(count)
            let p = point(at: t)
            let d = tangent(at: t)
            let half = width * (1 - taper * t) / 2
            left.append(CGPoint(x: p.x - d.dy * half, y: p.y + d.dx * half))
            right.append(CGPoint(x: p.x + d.dy * half, y: p.y - d.dx * half))
        }
        return (left, right)
    }

    /// The outline an arc is drawn with: a ribbon that narrows a little toward the end, finished by a
    /// small arrowhead whose tip stops at `end`, short of the disc of the person who is owed. The
    /// head never gets smaller than what reads on the thinnest arc, and shrinks away with the arc
    /// itself while it morphs to nothing. `headScale` above 1 makes it bolder for Increase Contrast.
    func arrowOutline(samples: Int = 24, taper: CGFloat = 0.3, headScale: CGFloat = 1) -> [CGPoint] {
        let count = max(samples, 2)
        let fade = min(max(width / 1.5, 0), 1)
        let endWidth = width * (1 - taper)
        let headHalf = max(endWidth * 1.2, 2.25 * headScale) * fade
        let headLength = max(endWidth * 2.2, 5 * headScale) * fade

        // walk back from the end along the curve to where the head begins
        let line = polyline(samples: count)
        var remaining = headLength
        var baseT: CGFloat = 0
        var index = count
        while index > 0 {
            let step = hypot(line[index].x - line[index - 1].x, line[index].y - line[index - 1].y)
            if step >= remaining {
                baseT = (CGFloat(index) - remaining / max(step, 0.0001)) / CGFloat(count)
                break
            }
            remaining -= step
            index -= 1
        }

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for step in 0...count {
            let fraction = CGFloat(step) / CGFloat(count)
            let t = baseT * fraction
            let p = point(at: t)
            let d = tangent(at: t)
            let half = width * (1 - taper * fraction) / 2
            left.append(CGPoint(x: p.x - d.dy * half, y: p.y + d.dx * half))
            right.append(CGPoint(x: p.x + d.dy * half, y: p.y - d.dx * half))
        }
        let base = point(at: baseT)
        let dx = end.x - base.x, dy = end.y - base.y
        let length = max(hypot(dx, dy), 0.0001)
        let across = CGVector(dx: -dy / length * headHalf, dy: dx / length * headHalf)
        let headLeft = CGPoint(x: base.x + across.dx, y: base.y + across.dy)
        let headRight = CGPoint(x: base.x - across.dx, y: base.y - across.dy)
        return left + [headLeft, end, headRight] + right.reversed()
    }

    /// The point at 0.5.
    var middle: CGPoint { point(at: 0.5) }

    /// How close the curve comes to `point`.
    func closestApproach(to point: CGPoint) -> CGFloat {
        polyline(samples: 48).map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? .greatestFiniteMagnitude
    }

    /// Distance from `location` to the curve's center line.
    func distance(to location: CGPoint) -> CGFloat {
        let line = polyline()
        var best = CGFloat.greatestFiniteMagnitude
        for index in 0..<(line.count - 1) {
            best = min(best, Self.distance(from: location, toSegment: line[index], line[index + 1]))
        }
        return best
    }

    static func lerp(_ a: ArcGeometry, _ b: ArcGeometry, _ t: CGFloat) -> ArcGeometry {
        ArcGeometry(
            start: a.start.lerp(to: b.start, t),
            control: a.control.lerp(to: b.control, t),
            end: a.end.lerp(to: b.end, t),
            width: a.width + (b.width - a.width) * t
        )
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

extension CGPoint {
    func moved(toward other: CGPoint, by distance: CGFloat) -> CGPoint {
        let dx = other.x - x, dy = other.y - y
        let length = max(hypot(dx, dy), 0.0001)
        return CGPoint(x: x + dx / length * distance, y: y + dy / length * distance)
    }

    func lerp(to other: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }
}
