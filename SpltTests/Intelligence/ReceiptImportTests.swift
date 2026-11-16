import Foundation
import SpltCore
import Testing
import UIKit
@testable import Splt

/// Counts scans and reads one item from every receipt.
private actor ScanCounter {
    private(set) var count = 0
    func add() { count += 1 }
}

private struct CountingScanner: ReceiptScanning {
    let counter: ScanCounter

    func scan(_ images: [CGImage]) async -> ParsedReceipt {
        await counter.add()
        var parsed = ParsedReceipt(currencyCode: "USD")
        parsed.items = [ReceiptLineItem(name: "Pasta", quantity: 1, unitPrice: nil, total: Money(minorUnits: 2000, currencyCode: "USD"))]
        parsed.total = Money(minorUnits: 2000, currencyCode: "USD")
        return parsed
    }
}

@Suite("Receipt import")
@MainActor
struct ReceiptImportTests {
    private func page() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: format).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
    }

    private func model(_ harness: ExpenseFormHarness, counter: ScanCounter) -> ExpenseFormModel {
        var dependencies = harness.dependencies
        dependencies.scanner = { _ in CountingScanner(counter: counter) }
        return ExpenseFormModel(
            mode: .add(groupID: harness.fixture.group.id, prefill: nil), services: harness.fixture.services, dependencies: dependencies
        )
    }

    @Test func theSpinnerShowsWhileThePhotoLoadsAndASecondPickIsIgnored() async throws {
        let harness = try ExpenseFormHarness()
        let counter = ScanCounter()
        let model = model(harness, counter: counter)
        let photo = page()
        let (gate, open) = AsyncStream<Void>.makeStream()

        let first = Task {
            await model.importReceipt {
                for await _ in gate { break }
                return photo
            }
        }
        while !model.isScanning { await Task.yield() }

        await model.importReceipt(imageData: photo)
        await model.importReceipt(pageImages: [UIImage(data: photo)!])
        #expect(model.isScanning)
        #expect(await counter.count == 0)

        open.yield()
        open.finish()
        await first.value
        #expect(!model.isScanning)
        #expect(await counter.count == 1)
        #expect(model.split.items.map(\.name) == ["Pasta"])
    }

    @Test func aPhotoThatDoesNotLoadSaysSoAndStopsTheSpinner() async throws {
        let harness = try ExpenseFormHarness()
        let counter = ScanCounter()
        let model = model(harness, counter: counter)
        await model.importReceipt { nil }
        #expect(!model.isScanning)
        #expect(model.scanNotice == "That photo could not be loaded.")
        #expect(await counter.count == 0)
    }

    @Test func cameraPagesAreScannedAndKept() async throws {
        let harness = try ExpenseFormHarness()
        let counter = ScanCounter()
        let model = model(harness, counter: counter)
        let image = try #require(UIImage(data: page()))
        await model.importReceipt(pageImages: [image, image])
        #expect(await counter.count == 1)
        let kept = try #require(model.receipt.pendingImage.flatMap { UIImage(data: $0)?.cgImage })
        #expect(kept.height == 600)
    }

    @Test func aScanThatMovesTheDateSaysSo() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.newExpense()
        var parsed = ParsedReceipt(currencyCode: "USD")
        parsed.items = [ReceiptLineItem(name: "Pasta", quantity: 1, unitPrice: nil, total: Money(minorUnits: 2000, currencyCode: "USD"))]
        parsed.total = Money(minorUnits: 2000, currencyCode: "USD")

        parsed.date = model.date
        model.apply(receipt: parsed)
        #expect(model.scanNotice?.contains("The date is now") == false)

        let earlier = try #require(Calendar.current.date(byAdding: .day, value: -3, to: model.date))
        parsed.date = earlier
        model.apply(receipt: parsed)
        #expect(model.date == earlier)
        #expect(model.scanNotice?.hasPrefix("Scanned 1 item.") == true)
        #expect(model.scanNotice?.contains("The date is now") == true)
    }
}
