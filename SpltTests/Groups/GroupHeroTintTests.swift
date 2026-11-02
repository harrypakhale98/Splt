import SpltCore
import SwiftUI
import Testing
import UIKit
@testable import Splt

@Suite("Group hero tint")
struct GroupHeroTintTests {
    private func group(_ id: Int, members: Int = 5) -> SplitGroup {
        func uuid(_ number: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))! }
        return SplitGroup(
            id: GroupID(rawValue: uuid(1000 + id)), name: "Group \(id)", currencyCode: "USD",
            memberIDs: (0..<members).map { PersonID(rawValue: uuid(id * 100 + $0)) }
        )
    }

    @Test func aGroupGetsOneDominantHueAndAtMostTwoMore() {
        for id in 0..<30 {
            let hues = GroupHeroTint.hues(for: group(id))
            #expect((1...3).contains(hues.count))
            #expect(Set(hues).count == hues.count)
            #expect(hues.allSatisfy { (0..<PersonPalette.count).contains($0) })
        }
    }

    @Test func theDominantHueBelongsToTheGroupAndStaysPut() {
        let first = group(1)
        #expect(GroupHeroTint.hues(for: first) == GroupHeroTint.hues(for: first))
        #expect(GroupHeroTint.hues(for: first).first == GroupHeroTint.hues(for: group(1, members: 2)).first)
        let dominants = Set((0..<30).map { GroupHeroTint.hues(for: group($0)).first })
        #expect(dominants.count >= 6, "groups should not all look alike")
    }

    @Test func aGroupWithNoMembersStillHasAHue() {
        let alone = SplitGroup(name: "Solo", currencyCode: "USD")
        #expect(GroupHeroTint.hues(for: alone).count == 1)
    }

    @Test func hueDistanceWrapsAroundTheWheel() {
        #expect(GroupHeroTint.distance(0, 11) == 1)
        #expect(GroupHeroTint.distance(2, 9) == 5)
        #expect(GroupHeroTint.distance(4, 4) == 0)
    }

    @Test func textStaysReadableOnEveryTint() {
        for dark in [false, true] {
            let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            let text: UIColor = dark ? .white : .black
            for index in 0..<PersonPalette.count {
                for role in [GroupHeroTint.Role.dominant, .accent] {
                    let background = UIColor(GroupHeroTint.color(index: index, role: role)).resolvedColor(with: traits)
                    let ratio = GroupHeroTint.contrast(text, background)
                    #expect(ratio >= 7, "hue \(index) \(role) \(dark ? "dark" : "light") only reaches \(ratio)")
                }
            }
        }
    }

    @Test func darkTintsAreDeeperThanLightOnes() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        for index in 0..<PersonPalette.count {
            let color = GroupHeroTint.color(index: index, role: .dominant)
            let bright = GroupHeroTint.luminance(UIColor(color).resolvedColor(with: light))
            let deep = GroupHeroTint.luminance(UIColor(color).resolvedColor(with: dark))
            #expect(deep < bright / 3)
        }
    }

    @Test func blendingMovesTowardTheBase() {
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        #expect(GroupHeroTint.blend(red, toward: .white, amount: 0) == red)
        var g: CGFloat = 0, other: CGFloat = 0, a: CGFloat = 0, r: CGFloat = 0
        GroupHeroTint.blend(red, toward: .white, amount: 0.5).getRed(&r, green: &g, blue: &other, alpha: &a)
        #expect(abs(r - 1) < 0.001 && abs(g - 0.5) < 0.001 && abs(other - 0.5) < 0.001)
        #expect(GroupHeroTint.contrast(.black, .white) > 20.9)
    }
}
