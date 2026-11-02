import CoreGraphics
import Foundation
import SpltCore

/// Where the amount pills go while someone is focused: one on each highlighted arc, none on top of
/// another pill, a person, a name or the amount in the middle.
struct PillPlacement: Equatable {
    var rect: CGRect
    /// Set when the full amount did not fit anywhere and the short form (whole units) is used.
    var isCompact: Bool

    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

enum OrbitPills {
    struct Request {
        var id: String
        var geometry: ArcGeometry
        var full: String
        var compact: String
    }

    static let height: CGFloat = 24

    /// A rough width for the text, enough to keep neighbors apart.
    static func size(of text: String, compact: Bool = false) -> CGSize {
        CGSize(width: CGFloat(text.count) * (compact ? 6.4 : 7.4) + 18, height: compact ? 20 : height)
    }

    /// The amount without decimals, such as "$316".
    static func compactText(_ money: Money, locale: Locale) -> String {
        money.decimalValue.formatted(
            .currency(code: money.currencyCode).locale(locale).precision(.fractionLength(0))
        )
    }

    /// Places the widest arcs first. Each pill slides along its arc and away from it until it finds
    /// room, then falls back to the short text, and last of all to the least crowded spot.
    static func place(_ requests: [Request], in layout: OrbitLayout) -> [String: PillPlacement] {
        var placed: [String: PillPlacement] = [:]
        var taken: [CGRect] = []
        let fixed = obstacles(in: layout)
        let bounds = CGRect(origin: .zero, size: layout.size)

        for request in requests.sorted(by: { $0.geometry.width > $1.geometry.width }) {
            var best: (placement: PillPlacement, penalty: Int)?
            for compact in [false, true] {
                let text = compact ? request.compact : request.full
                let size = Self.size(of: text, compact: compact)
                for candidate in candidates(for: request.geometry, size: size, in: layout) {
                    let rect = CGRect(x: candidate.x - size.width / 2, y: candidate.y - size.height / 2, width: size.width, height: size.height)
                    guard bounds.insetBy(dx: -4, dy: -4).contains(rect) else { continue }
                    let penalty = collisions(of: rect, with: fixed, taken: taken)
                    let placement = PillPlacement(rect: rect, isCompact: compact)
                    if penalty == 0 {
                        best = (placement, 0)
                        break
                    }
                    if penalty < (best?.penalty ?? .max) { best = (placement, penalty) }
                }
                if best?.penalty == 0 { break }
            }
            if let best {
                placed[request.id] = best.placement
                taken.append(best.placement.rect.insetBy(dx: -4, dy: -3))
            }
        }
        return placed
    }

    // MARK: Pieces

    private struct Obstacles {
        var circles: [(center: CGPoint, radius: CGFloat)]
        var rects: [CGRect]
    }

    private static func obstacles(in layout: OrbitLayout) -> Obstacles {
        var circles = layout.positions.map { (center: $0, radius: layout.nodeRadius + 3) }
        circles.append((layout.center, layout.centerRadius + 4))
        var rects: [CGRect] = []
        if layout.labelStyle != .hidden {
            for index in 0..<layout.count {
                let point = layout.labelPosition(index)
                rects.append(CGRect(x: point.x - 26, y: point.y - 8, width: 52, height: 16))
            }
        }
        return Obstacles(circles: circles, rects: rects)
    }

    private static func candidates(for geometry: ArcGeometry, size: CGSize, in layout: OrbitLayout) -> [CGPoint] {
        var points: [CGPoint] = []
        for extra in [0, 14, 28, 44, 60] as [CGFloat] {
            for t in [0.5, 0.4, 0.6, 0.3, 0.7, 0.22, 0.78, 0.15, 0.85] as [CGFloat] {
                let point = geometry.point(at: t)
                let dx = point.x - layout.center.x, dy = point.y - layout.center.y
                let length = max(hypot(dx, dy), 0.0001)
                let offset = geometry.width / 2 + size.height / 2 + 2 + extra
                points.append(CGPoint(x: point.x + dx / length * offset, y: point.y + dy / length * offset))
            }
        }
        return points
    }

    private static func collisions(of rect: CGRect, with fixed: Obstacles, taken: [CGRect]) -> Int {
        var count = 0
        for circle in fixed.circles where intersects(rect, circle.center, circle.radius) { count += 1 }
        for other in fixed.rects where rect.intersects(other) { count += 1 }
        for other in taken where rect.intersects(other) { count += 1 }
        return count
    }

    static func intersects(_ rect: CGRect, _ center: CGPoint, _ radius: CGFloat) -> Bool {
        let x = min(max(center.x, rect.minX), rect.maxX)
        let y = min(max(center.y, rect.minY), rect.maxY)
        return hypot(center.x - x, center.y - y) < radius
    }
}
