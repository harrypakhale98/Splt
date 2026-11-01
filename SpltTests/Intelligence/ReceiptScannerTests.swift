import CoreGraphics
import CoreText
import Foundation
import SpltCore
import Testing
@testable import Splt

private struct StubRecognizer: ReceiptTextRecognizing {
    var lines: [ReceiptTextLine]
    var fails = false

    func recognizeLines(in image: CGImage) async throws -> [ReceiptTextLine] {
        if fails { throw OnDeviceModel.TimedOut() }
        return lines
    }
}

private struct StubRepairer: ReceiptNameRepairing {
    func repairNames(in receipt: ParsedReceipt) async -> ParsedReceipt {
        var changed = receipt
        changed.merchant = "Repaired"
        return changed
    }
}

private func blankImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    return context.makeImage()!
}

private func fixtureLines() -> [ReceiptTextLine] {
    let rows: [(String, CGFloat)] = [
        ("CAFE ROMA", 0.9), ("Espresso 2.50", 0.8), ("Croissant 1.90", 0.75), ("Total 4.40", 0.6)
    ]
    return rows.map { ReceiptTextLine(text: $0.0, boundingBox: CGRect(x: 0.1, y: $0.1, width: 0.5, height: 0.03)) }
}

/// Draws black text on white with Core Text so recognition can run on a real bitmap.
private func renderReceipt(_ lines: [String]) -> CGImage {
    let width = 900, height = 140 + lines.count * 90
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Menlo" as CFString, 44, nil)
    for (index, text) in lines.enumerated() {
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.textPosition = CGPoint(x: 50, y: CGFloat(height - 110 - index * 90))
        CTLineDraw(line, context)
    }
    return context.makeImage()!
}

@Suite("Receipt scanner")
struct ReceiptScannerTests {
    @Test func scansThroughTheRecognizerAndParser() async {
        let scanner = VisionReceiptScanner(recognizer: StubRecognizer(lines: fixtureLines()), repairer: nil)
        let receipt = await scanner.scan([blankImage()])
        #expect(receipt.merchant == "Cafe Roma")
        #expect(receipt.items.count == 2)
        #expect(receipt.total == Money(minorUnits: 440, currencyCode: "USD"))
        #expect(receipt.isConsistent)
    }

    @Test func recognitionFailureGivesAnEmptyReceiptNotAnError() async {
        let scanner = VisionReceiptScanner(recognizer: StubRecognizer(lines: [], fails: true), repairer: nil)
        let receipt = await scanner.scan([blankImage()])
        #expect(receipt.items.isEmpty)
        #expect(receipt.issues == [.noItems, .missingTotal])
        #expect(await scanner.scan([]).items.isEmpty)
        #expect(await scanner.scan(photoData: Data([1, 2, 3])).items.isEmpty)
    }

    @Test func repairerRunsOnlyWhenThereAreItems() async {
        let scanner = VisionReceiptScanner(recognizer: StubRecognizer(lines: fixtureLines()), repairer: StubRepairer())
        #expect(await scanner.scan([blankImage()]).merchant == "Repaired")
        let empty = VisionReceiptScanner(recognizer: StubRecognizer(lines: []), repairer: StubRepairer())
        #expect(await empty.scan([blankImage()]).merchant == nil)
    }

    /// Text recognition models are not dependable inside the simulator, so this runs on real hardware and the Mac.
    private static let canRunVision: Bool = {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }()

    @Test(.enabled(if: Self.canRunVision))
    func visionReadsARenderedReceipt() async throws {
        let image = renderReceipt(["Coffee Corner", "Latte        4.50", "Muffin       3.25", "Subtotal     7.75", "Tax          0.62", "Total        8.37"])
        let scanner = VisionReceiptScanner(repairer: nil)
        let receipt = await scanner.scan([image])
        #expect(receipt.items.count == 2)
        #expect(receipt.total == Money(minorUnits: 837, currencyCode: "USD"))
        #expect(receipt.isConsistent)
    }
}

@Suite("Receipt name repair")
struct ReceiptNameRepairTests {
    private func receipt() -> ParsedReceipt {
        let usd = { (minor: Int64) in Money(minorUnits: minor, currencyCode: "USD") }
        return ParsedReceipt(
            merchant: "CAFE R0MA",
            currencyCode: "USD",
            items: [
                ReceiptLineItem(name: "CHKN SAL", quantity: 1, unitPrice: nil, total: usd(900)),
                ReceiptLineItem(name: "Espreso", quantity: 1, unitPrice: nil, total: usd(250))
            ],
            total: usd(1150)
        )
    }

    @Test func closeSuggestionsAreApplied() {
        let result = FoundationModelsNameRepairer.apply("Cafe Roma", ["Chicken Salad", "Espresso"], to: receipt())
        #expect(result.merchant == "Cafe Roma")
        #expect(result.items.map(\.name) == ["Chicken Salad", "Espresso"])
        #expect(result.items.map(\.total.minorUnits) == [900, 250])
    }

    @Test func farFetchedSuggestionsAreIgnored() {
        let result = FoundationModelsNameRepairer.apply("Luxury Steakhouse", ["Wagyu Ribeye Tasting Menu", "Espresso"], to: receipt())
        #expect(result.merchant == "CAFE R0MA")
        #expect(result.items.map(\.name) == ["CHKN SAL", "Espresso"])
    }

    @Test func wrongItemCountChangesNothing() {
        let original = receipt()
        #expect(FoundationModelsNameRepairer.apply("Cafe Roma", ["Only one"], to: original) == original)
    }

    @Test func emptyAndOverlongNamesAreRejected() {
        #expect(!ReceiptNameCheck.accepts("", replacing: "Latte"))
        #expect(!ReceiptNameCheck.accepts("1234", replacing: "Latte"))
        #expect(!ReceiptNameCheck.accepts(String(repeating: "a", count: 80), replacing: "aaaa"))
        #expect(ReceiptNameCheck.accepts("Latte", replacing: "LATTE"))
    }
}
