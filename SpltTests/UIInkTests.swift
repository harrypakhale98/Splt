import SwiftUI
import Testing
import UIKit
@testable import Splt

@Suite("Ink")
struct UIInkTests {
    private func luminance(_ color: Color, _ style: UIUserInterfaceStyle) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return ContrastInk.luminance(.init(red: Double(red), green: Double(green), blue: Double(blue)))
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func textRolesAreLegibleOnPaperAndSheet(style: UIUserInterfaceStyle) {
        for background in [Ink.paper, Ink.sheet] {
            for foreground in [Ink.text, Ink.secondary, Ink.owed, Ink.owe] {
                let lighter = max(luminance(foreground, style), luminance(background, style))
                let darker = min(luminance(foreground, style), luminance(background, style))
                let ratio = (lighter + 0.05) / (darker + 0.05)
                #expect(ratio >= 4.5)
            }
        }
    }

    @Test func directionFollowsTheSign() {
        #expect(Ink.direction(of: 1) == Ink.owed)
        #expect(Ink.direction(of: -1) == Ink.owe)
        #expect(Ink.direction(of: 0) == Ink.text)
    }
}
