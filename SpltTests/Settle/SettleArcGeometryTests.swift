import CoreGraphics
import Testing
@testable import Splt

@Suite("Settle arc")
struct SettleArcGeometryTests {
    private let geometry = SettleArcGeometry(
        start: CGPoint(x: 40, y: 100), end: CGPoint(x: 340, y: 100), radius: 30, peak: 50
    )

    @Test func theArcRunsBetweenTheEdgesOfTheAvatars() {
        let curve = geometry.controlPoints(contraction: 0)
        #expect(curve.from == CGPoint(x: 70, y: 100))
        #expect(curve.to == CGPoint(x: 310, y: 100))
        #expect(curve.control.x == 190)
        #expect(curve.control.y == 0)
    }

    @Test func positionAlongTheArcIsLinearInX() {
        let start = geometry.point(at: 0, contraction: 0)
        let middle = geometry.point(at: 0.5, contraction: 0)
        let quarter = geometry.point(at: 0.25, contraction: 0)
        #expect(start == CGPoint(x: 70, y: 100))
        #expect(middle.x == 190)
        #expect(abs(quarter.x - 130) < 0.001)
        #expect(middle.y == 50)
    }

    @Test func theKnobStaysClearOfBothPeople() {
        let inset = SettleArcGeometry(
            start: CGPoint(x: 40, y: 100), end: CGPoint(x: 340, y: 100), radius: 30, peak: 50, knobInset: 12
        )
        // the arc runs 70...310, so the knob runs 82...298
        #expect(abs(inset.point(at: inset.knobT(for: 0), contraction: 0).x - 82) < 0.001)
        #expect(abs(inset.point(at: inset.knobT(for: 1), contraction: 0).x - 298) < 0.001)
        #expect(abs(inset.point(at: inset.knobT(for: 0.5), contraction: 0).x - 190) < 0.001)
    }

    @Test func aFingerMapsBackToTheShareItPointsAt() {
        let inset = SettleArcGeometry(
            start: CGPoint(x: 40, y: 100), end: CGPoint(x: 340, y: 100), radius: 30, peak: 50, knobInset: 12
        )
        for share in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let x = inset.point(at: inset.knobT(for: share), contraction: 0).x
            #expect(abs(inset.fraction(atX: x) - share) < 0.0001)
        }
        #expect(inset.fraction(atX: 0) == 0)
        #expect(inset.fraction(atX: 400) == 1)
    }

    @Test func contractingPullsTheEndsToTheMiddleAndFlattens() {
        let half = geometry.controlPoints(contraction: 0.5)
        #expect(half.from.x == 130)
        #expect(half.to.x == 250)
        #expect(half.control.y == 50)
        let done = geometry.controlPoints(contraction: 1)
        #expect(done.from == done.to)
        #expect(done.from.x == 190)
        #expect(done.control.y == 100)
    }

    @Test func contractionIsClamped() {
        #expect(geometry.controlPoints(contraction: 3).from == geometry.controlPoints(contraction: 1).from)
        #expect(geometry.controlPoints(contraction: -1).to == geometry.controlPoints(contraction: 0).to)
        #expect(geometry.point(at: 5, contraction: 0) == geometry.point(at: 1, contraction: 0))
    }
}
