import CoreGraphics
import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Orbit geometry")
struct OrbitGeometryTests {
    private let square = CGSize(width: 340, height: 340)

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    @Test func peopleSitEvenlyOnTheRing() {
        for count in 2...12 {
            let layout = OrbitLayout(size: square, count: count)
            #expect(layout.positions.count == count)
            for point in layout.positions {
                #expect(abs(distance(point, layout.center) - layout.ringRadius) < 0.001)
            }
            let steps = (0..<count).map { distance(layout.positions[$0], layout.positions[($0 + 1) % count]) }
            #expect((steps.max() ?? 0) - (steps.min() ?? 0) < 0.001, "uneven spacing for \(count)")
        }
    }

    @Test func youStartAtTheTopAndTwoPeopleSitSideBySide() {
        let many = OrbitLayout(size: square, count: 5)
        #expect(abs(many.positions[0].x - many.center.x) < 0.001)
        #expect(many.positions[0].y < many.center.y)

        let pair = OrbitLayout(size: square, count: 2)
        #expect(abs(pair.positions[0].y - pair.center.y) < 0.001)
        #expect(pair.positions[0].x < pair.center.x)
        #expect(pair.positions[1].x > pair.center.x)
    }

    @Test func everyoneFitsInsideTheCanvasAndNeverTouches() {
        for size in [CGSize(width: 340, height: 340), CGSize(width: 260, height: 260), CGSize(width: 420, height: 380)] {
            for count in 2...12 {
                let layout = OrbitLayout(size: size, count: count)
                for point in layout.positions {
                    #expect(point.x - layout.nodeRadius >= 0 && point.x + layout.nodeRadius <= size.width)
                    #expect(point.y - layout.nodeRadius >= 0 && point.y + layout.nodeRadius <= size.height)
                }
                if count >= 3 {
                    let gap = distance(layout.positions[0], layout.positions[1])
                    #expect(gap > layout.nodeRadius * 2, "avatars touch at \(count)")
                }
            }
        }
    }

    @Test func labelsCollapseAsTheRingFills() {
        #expect(OrbitLayout(size: square, count: 2).labelStyle == .name)
        #expect(OrbitLayout(size: square, count: 6).labelStyle == .name)
        #expect(OrbitLayout(size: square, count: 7).labelStyle == .compact)
        #expect(OrbitLayout(size: square, count: 9).labelStyle == .compact)
        #expect(OrbitLayout(size: square, count: 12).labelStyle == .hidden)
    }

    @Test func avatarsShrinkAsMorePeopleJoin() {
        let sizes = [2, 5, 8, 12].map { OrbitLayout(size: square, count: $0).nodeRadius }
        #expect(sizes == sizes.sorted(by: >))
        #expect(sizes.last ?? 0 >= 8)
    }

    @Test func emptyAndSinglePersonRingsDoNotCrash() {
        #expect(OrbitLayout(size: square, count: 0).positions.isEmpty)
        #expect(OrbitLayout(size: square, count: 1).positions.count == 1)
        #expect(OrbitLayout(size: .zero, count: 4).positions.count == 4)
    }

    // MARK: Arcs

    @Test func arcWidthIsProportionalAndClamped() {
        let layout = OrbitLayout(size: square, count: 4)
        let full = layout.arcWidth(amount: 1000, largest: 1000)
        let half = layout.arcWidth(amount: 500, largest: 1000)
        let tiny = layout.arcWidth(amount: 1, largest: 1000)
        #expect(full == layout.maxArcWidth)
        #expect(tiny >= layout.minArcWidth)
        #expect(abs((half - layout.minArcWidth) - (full - layout.minArcWidth) / 2) < 0.001)
        #expect(layout.arcWidth(amount: 5000, largest: 1000) == full)
        #expect(layout.arcWidth(amount: 0, largest: 1000) == layout.minArcWidth)
        #expect(layout.arcWidth(amount: 10, largest: 0) == layout.minArcWidth)
    }

    @Test func arcsLeaveAndEnterJustOutsideTheAvatars() throws {
        let layout = OrbitLayout(size: square, count: 5)
        let arc = try #require(layout.arc(from: 0, to: 2, width: 6))
        let fromGap = distance(arc.start, layout.positions[0])
        let toGap = distance(arc.end, layout.positions[2])
        #expect(abs(fromGap - (layout.nodeRadius + 3)) < 0.001)
        #expect(abs(toGap - (layout.nodeRadius + 3)) < 0.001)
        #expect(layout.arc(from: 1, to: 1, width: 6) == nil)
        #expect(layout.arc(from: 0, to: 9, width: 6) == nil)
    }

    @Test func arcsBowTowardTheMiddle() throws {
        let layout = OrbitLayout(size: square, count: 6)
        let arc = try #require(layout.arc(from: 0, to: 2, width: 6))
        let straightMid = CGPoint(
            x: (layout.positions[0].x + layout.positions[2].x) / 2,
            y: (layout.positions[0].y + layout.positions[2].y) / 2
        )
        #expect(distance(arc.middle, layout.center) < distance(straightMid, layout.center))
    }

    @Test func oppositePeopleBendAroundTheCenter() throws {
        for count in [2, 4, 6, 12] {
            let layout = OrbitLayout(size: square, count: count)
            let arc = try #require(layout.arc(from: 0, to: count / 2, width: 6))
            #expect(distance(arc.middle, layout.center) > layout.ringRadius * 0.12, "runs through the middle at \(count)")
        }
    }

    @Test func curveEndpointsAndMidpointAreExact() {
        let arc = ArcGeometry(start: CGPoint(x: 0, y: 0), control: CGPoint(x: 50, y: 100), end: CGPoint(x: 100, y: 0), width: 8)
        #expect(arc.point(at: 0) == arc.start)
        #expect(arc.point(at: 1) == arc.end)
        #expect(arc.middle == CGPoint(x: 50, y: 50))
        let tangent = arc.tangent(at: 0)
        #expect(abs(hypot(tangent.dx, tangent.dy) - 1) < 0.0001)
    }

    @Test func ribbonsNarrowTowardTheEnd() {
        let arc = ArcGeometry(start: CGPoint(x: 0, y: 0), control: CGPoint(x: 50, y: 60), end: CGPoint(x: 100, y: 0), width: 10)
        let ribbon = arc.ribbon(samples: 8)
        #expect(ribbon.left.count == 9 && ribbon.right.count == 9)
        let first = distance(ribbon.left[0], ribbon.right[0])
        let last = distance(ribbon.left[8], ribbon.right[8])
        #expect(abs(first - 10) < 0.001)
        #expect(last < first)
        #expect(abs(last - 10 * 0.45) < 0.01)
    }

    @Test func interpolationMeetsBothEnds() {
        let a = ArcGeometry(start: .zero, control: CGPoint(x: 10, y: 10), end: CGPoint(x: 20, y: 0), width: 4)
        let b = ArcGeometry(start: CGPoint(x: 10, y: 10), control: CGPoint(x: 30, y: 30), end: CGPoint(x: 40, y: 10), width: 12)
        #expect(ArcGeometry.lerp(a, b, 0) == a)
        #expect(ArcGeometry.lerp(a, b, 1) == b)
        #expect(ArcGeometry.lerp(a, b, 0.5).width == 8)
    }

    @Test func distanceToACurveIsZeroOnItAndGrowsAway() {
        let arc = ArcGeometry(start: .zero, control: CGPoint(x: 50, y: 0), end: CGPoint(x: 100, y: 0), width: 6)
        #expect(arc.distance(to: CGPoint(x: 40, y: 0)) < 0.001)
        #expect(abs(arc.distance(to: CGPoint(x: 40, y: 30)) - 30) < 0.001)
    }
}

@Suite("Orbit scene")
struct OrbitSceneTests {
    private let ids = (0..<6).map { _ in PersonID() }

    private func transfer(_ from: Int, _ to: Int, _ cents: Int64) -> OrbitTransfer {
        OrbitTransfer(debtor: ids[from], creditor: ids[to], amount: usdAmount(cents))
    }

    private func scene(count: Int = 4, _ transfers: [OrbitTransfer]) -> OrbitScene {
        OrbitScene(size: CGSize(width: 340, height: 340), people: Array(ids.prefix(count)), transfers: transfers)
    }

    @Test func arcsAreProportionalToTheLargestDebt() throws {
        let scene = scene([transfer(1, 0, 3000), transfer(2, 0, 1500), transfer(3, 0, 300)])
        let widths = scene.arcs.map(\.geometry.width)
        #expect(widths == widths.sorted(by: >))
        #expect(scene.largest == 3000)
        #expect(scene.width(of: transfer(1, 0, 3000)) == scene.layout.maxArcWidth)
        #expect(scene.width(of: transfer(3, 0, 300)) < scene.width(of: transfer(2, 0, 1500)))
    }

    @Test func transfersWithUnknownPeopleAreNotDrawn() {
        let scene = scene(count: 2, [transfer(0, 1, 100), transfer(0, 5, 100)])
        #expect(scene.arcs.count == 1)
    }

    @Test func focusDimsEverythingThatDoesNotTouchThePerson() {
        let near = transfer(1, 0, 1000)
        let far = transfer(2, 3, 1000)
        let scene = scene([near, far])
        let focus = OrbitFocus.person(ids[0])
        #expect(scene.emphasis(of: near, focus: focus) == .highlighted)
        #expect(scene.emphasis(of: far, focus: focus) == .dimmed)
        #expect(scene.emphasis(of: near, focus: .none) == .normal)
        #expect(scene.emphasis(of: ids[0], focus: focus) == .highlighted)
        #expect(scene.emphasis(of: ids[1], focus: focus) == .normal)
        #expect(scene.emphasis(of: ids[2], focus: focus) == .dimmed)
        #expect(scene.emphasis(of: ids[2], focus: .none) == .normal)
    }

    @Test func tappingTheFocusedPersonClearsTheFocus() {
        var focus = OrbitFocus.none
        focus.toggle(ids[1])
        #expect(focus == .person(ids[1]))
        focus.toggle(ids[2])
        #expect(focus == .person(ids[2]))
        focus.toggle(ids[2])
        #expect(focus == .none)
    }

    @Test func tapsFindPeopleThenArcsThenNothing() throws {
        let scene = scene(count: 4, [transfer(1, 0, 1000)])
        for (index, id) in ids.prefix(4).enumerated() {
            #expect(scene.hit(at: scene.layout.positions[index]) == .person(id))
        }
        let arc = try #require(scene.arc(for: transfer(1, 0, 1000)))
        #expect(scene.hit(at: arc.middle) == .transfer(transfer(1, 0, 1000).id))
        #expect(scene.hit(at: CGPoint(x: 2, y: 2)) == .nothing)
    }

    @Test func targetsAreAtLeastFortyFourPointsAcross() {
        let scene = OrbitScene(size: CGSize(width: 300, height: 300), people: ids + ids.map { _ in PersonID() }, transfers: [])
        let spot = scene.layout.positions[3]
        #expect(scene.hit(at: CGPoint(x: spot.x + 20, y: spot.y)) != .nothing)
    }

    @Test func aPersonWinsOverAnArcThroughThem() {
        let scene = scene(count: 4, [transfer(1, 3, 1000)])
        let position = scene.layout.positions[2]
        #expect(scene.hit(at: position) == .person(ids[2]))
    }
}

@Suite("Orbit morph")
struct OrbitMorphTests {
    private let a = PersonID(), b = PersonID(), c = PersonID(), d = PersonID()

    private func transfer(_ from: PersonID, _ to: PersonID, _ cents: Int64) -> OrbitTransfer {
        OrbitTransfer(debtor: from, creditor: to, amount: usdAmount(cents))
    }

    private func check(_ old: [OrbitTransfer], _ new: [OrbitTransfer]) -> [MorphPair] {
        let pairs = OrbitMorph.pairs(from: old, to: new)
        let starts = pairs.compactMap(\.start).map(\.id)
        let ends = pairs.compactMap(\.end)
        let mergeAndStay = pairs.filter { $0.kind == .stay || $0.kind == .merge || $0.kind == .vanish }.compactMap(\.start).map(\.id)
        let stayAndSplit = pairs.filter { $0.kind == .stay || $0.kind == .split || $0.kind == .appear }.compactMap(\.end).map(\.id)
        #expect(Set(mergeAndStay) == Set(old.map(\.id)), "every old arc starts a pair")
        #expect(mergeAndStay.count == old.count)
        #expect(Set(stayAndSplit) == Set(new.map(\.id)), "every new arc ends a pair")
        #expect(stayAndSplit.count == new.count)
        #expect(starts.count + ends.count >= 0)
        #expect(Set(pairs.map(\.id)).count == pairs.count)
        return pairs
    }

    @Test func aChainMergesIntoOneArc() {
        let old = [transfer(a, b, 1000), transfer(b, c, 1000)]
        let new = [transfer(a, c, 1000)]
        let pairs = check(old, new)
        #expect(pairs.filter { $0.kind == .merge }.count == 2)
        #expect(pairs.filter { $0.kind == .split }.count == 1)
        #expect(pairs.allSatisfy { $0.kind != .stay })
    }

    @Test func arcsThatStayJustResize() {
        let old = [transfer(a, b, 1000), transfer(c, b, 500)]
        let new = [transfer(a, b, 1200), transfer(c, b, 500)]
        let pairs = check(old, new)
        #expect(pairs.count == 2)
        #expect(pairs.allSatisfy { $0.kind == .stay })
        #expect(pairs.first { $0.end?.id == transfer(a, b, 0).id }?.start?.amount == usdAmount(1000))
    }

    @Test func mergesPreferTheArcThatSharesAPerson() {
        let old = [transfer(a, b, 1000), transfer(c, d, 1000)]
        let new = [transfer(a, d, 1000), transfer(c, b, 1000)]
        let pairs = check(old, new)
        let merge = pairs.first { $0.kind == .merge && $0.start?.id == transfer(a, b, 0).id }
        #expect(merge?.end.map { Set([$0.debtor, $0.creditor]).contains(a) || Set([$0.debtor, $0.creditor]).contains(b) } == true)
    }

    @Test func goingFromNothingAppearsAndToNothingVanishes() {
        let some = [transfer(a, b, 1000)]
        #expect(check([], some).map(\.kind) == [.appear])
        #expect(check(some, []).map(\.kind) == [.vanish])
        #expect(check([], []).isEmpty)
    }

    @Test func extraArcsGrowFromTheOnesThatLeft() {
        let old = [transfer(a, b, 1000)]
        let new = [transfer(a, b, 1000), transfer(c, b, 400)]
        let pairs = check(old, new)
        #expect(pairs.map(\.kind).sorted { "\($0)" < "\($1)" } == [.appear, .stay])
    }

    @Test func widthsFollowTheKind() throws {
        let size = CGSize(width: 340, height: 340)
        let people = [a, b, c, d]
        let old = OrbitScene(size: size, people: people, transfers: [transfer(a, b, 1000), transfer(b, c, 1000)])
        let new = OrbitScene(size: size, people: people, transfers: [transfer(a, c, 1000)])
        for pair in OrbitMorph.pairs(from: old.transfers, to: new.transfers) {
            let shapes = try #require(OrbitMorph.geometry(for: pair, in: old, target: new))
            switch pair.kind {
            case .merge: #expect(shapes.to.width == 0 && shapes.from.width > 0)
            case .split: #expect(shapes.from.width == 0 && shapes.to.width > 0)
            default: Issue.record("unexpected \(pair.kind)")
            }
        }
    }
}
