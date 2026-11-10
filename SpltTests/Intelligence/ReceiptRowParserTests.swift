import CoreGraphics
import Foundation
import SpltCore
import Testing
@testable import Splt

/// Builds fixture lines the way Vision would report them: normalised, origin at the bottom left.
private struct Page {
    var lines: [ReceiptTextLine] = []
    private var cursor: CGFloat = 0.95

    mutating func row(_ left: String, _ right: String? = nil, height: CGFloat = 0.02, jitter: CGFloat = 0) {
        lines.append(ReceiptTextLine(text: left, boundingBox: CGRect(x: 0.08, y: cursor, width: 0.5, height: height)))
        if let right {
            lines.append(ReceiptTextLine(text: right, boundingBox: CGRect(x: 0.75, y: cursor + jitter, width: 0.15, height: height)))
        }
        cursor -= height + 0.012
    }

    func shuffled() -> [ReceiptTextLine] { lines.reversed() }
}

private func usdMoney(_ minor: Int64) -> Money { Money(minorUnits: minor, currencyCode: "USD") }

private let options = ReceiptParsingOptions(
    defaultCurrencyCode: "USD",
    locale: Locale(identifier: "en_US"),
    referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
)

/// One printed row per string, top to bottom.
private func receipt(_ rows: [String]) -> ParsedReceipt {
    var page = Page()
    for row in rows { page.row(row) }
    return ReceiptRowParser.parse(lines: page.lines, options: options)
}

@Suite("Receipt row parsing")
struct ReceiptRowParserTests {
    @Test func readsASplitColumnRestaurantReceipt() {
        var page = Page()
        page.row("CORNER BISTRO", height: 0.04)
        page.row("12 Main Street")
        page.row("Table 5   Server: Dana")
        page.row("03/14/2026 19:45")
        page.row("2 x Margherita Pizza", "24.00", jitter: 0.004)
        page.row("Caesar Salad", "9.50")
        page.row("Sparkling Water", "3.50")
        page.row("Subtotal", "37.00")
        page.row("Sales Tax 8.5%", "3.15")
        page.row("Tip", "7.40")
        page.row("TOTAL", "47.55")
        page.row("VISA ****1234", "47.55")
        page.row("Thank you!")

        let receipt = ReceiptRowParser.parse(lines: page.shuffled(), options: options)
        #expect(receipt.merchant == "Corner Bistro")
        #expect(receipt.items.map(\.name) == ["Margherita Pizza", "Caesar Salad", "Sparkling Water"])
        #expect(receipt.items.map(\.quantity) == [2, 1, 1])
        #expect(receipt.items[0].unitPrice == usdMoney(1200))
        #expect(receipt.items.map(\.total) == [usdMoney(2400), usdMoney(950), usdMoney(350)])
        #expect(receipt.subtotal == usdMoney(3700))
        #expect(receipt.tax == usdMoney(315))
        #expect(receipt.tip == usdMoney(740))
        #expect(receipt.total == usdMoney(4755))
        #expect(receipt.currencyCode == "USD")
        #expect(receipt.issues.isEmpty)
        #expect(receipt.isConsistent)

        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: try! #require(receipt.date))
        #expect(parts.year == 2026 && parts.month == 3 && parts.day == 14)
        #expect(parts.hour == 19 && parts.minute == 45)
    }

    @Test func readsSingleLineRowsWithPricesInTheText() {
        var page = Page()
        page.row("Trader Joes", height: 0.035)
        page.row("Bananas 1.29")
        page.row("Oat Milk 3.99 T")
        page.row("Coupon -1.00")
        page.row("Subtotal 4.28")
        page.row("Tax 0.32")
        page.row("Total $4.60")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.items.map(\.name) == ["Bananas", "Oat Milk", "Coupon"])
        #expect(receipt.items.map(\.total) == [usdMoney(129), usdMoney(399), usdMoney(-100)])
        #expect(receipt.subtotal == usdMoney(428))
        #expect(receipt.total == usdMoney(460))
        #expect(receipt.isConsistent)
    }

    @Test func attachesQuantityDetailRowsToTheItemAbove() {
        var page = Page()
        page.row("Burger Shack", height: 0.04)
        page.row("Classic Burger")
        page.row("3 @ 8.00", "24.00")
        page.row("Fries", "5.00")
        page.row("2 x 2.50")
        page.row("Total", "29.00")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.items.count == 2)
        #expect(receipt.items[0].name == "Classic Burger")
        #expect(receipt.items[0].quantity == 3)
        #expect(receipt.items[0].unitPrice == usdMoney(800))
        #expect(receipt.items[0].total == usdMoney(2400))
        #expect(receipt.items[1].quantity == 2)
        #expect(receipt.items[1].unitPrice == usdMoney(250))
        #expect(receipt.items[1].total == usdMoney(500))
        #expect(receipt.total == usdMoney(2900))
        #expect(receipt.isConsistent)
    }

    @Test func readsTrailingQuantityMarks() {
        var page = Page()
        page.row("Cafe")
        page.row("Latte x2", "9.00")
        page.row("Total", "9.00")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.items.first?.name == "Latte")
        #expect(receipt.items.first?.quantity == 2)
        #expect(receipt.items.first?.unitPrice == usdMoney(450))
    }

    @Test func flagsReceiptsThatDoNotAddUp() {
        var page = Page()
        page.row("Deli", height: 0.04)
        page.row("Sandwich", "8.00")
        page.row("Soup", "5.00")
        page.row("Subtotal", "13.00")
        page.row("Tax", "1.00")
        page.row("Total", "15.00")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.issues == [.totalDiffersFromParts(difference: 100)])
        #expect(!receipt.isConsistent)
    }

    @Test func flagsItemsThatMissTheSubtotal() {
        var page = Page()
        page.row("Deli", height: 0.04)
        page.row("Sandwich", "8.00")
        page.row("Subtotal", "13.00")
        page.row("Total", "13.00")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.issues.contains(.itemsDifferFromSubtotal(difference: -500)))
    }

    @Test func missingTotalAndMissingItemsAreReported() {
        var page = Page()
        page.row("Deli", height: 0.04)
        page.row("Sandwich", "8.00")
        #expect(ReceiptRowParser.parse(lines: page.lines, options: options).issues == [.missingTotal])
        #expect(ReceiptRowParser.parse(lines: [], options: options).issues == [.noItems, .missingTotal])
    }

    @Test func feesAfterTheSubtotalAreKeptApartFromItems() {
        var page = Page()
        page.row("Pizza Place", height: 0.04)
        page.row("Large Pizza", "18.00")
        page.row("Subtotal", "18.00")
        page.row("Delivery Fee", "3.00")
        page.row("Promo Discount", "-2.00")
        page.row("Tax", "1.50")
        page.row("Total", "20.50")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.items.count == 1)
        #expect(receipt.otherCharges == usdMoney(100))
        #expect(receipt.isConsistent)
    }

    @Test func multipleTaxLinesAreAdded() {
        var page = Page()
        page.row("Shop", height: 0.04)
        page.row("Shirt", "20.00")
        page.row("Subtotal", "20.00")
        page.row("CGST 9%", "1.80")
        page.row("SGST 9%", "1.80")
        page.row("Total", "23.60")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.tax == usdMoney(360))
        #expect(receipt.isConsistent)
    }

    @Test func totalOnItsOwnRowStillCounts() {
        var page = Page()
        page.row("Shop", height: 0.04)
        page.row("Shirt", "20.00")
        page.row("Subtotal", "20.00")
        page.row("TOTAL")
        page.row("20.00")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.total == usdMoney(2000))
    }

    @Test func tipWrittenAfterTheTotalUpdatesIt() {
        var page = Page()
        page.row("Grill", height: 0.04)
        page.row("Steak", "30.00")
        page.row("Subtotal", "30.00")
        page.row("Total", "30.00")
        page.row("Tip", "6.00")
        page.row("Total", "36.00")
        page.row("Visa", "36.00")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.tip == usdMoney(600))
        #expect(receipt.total == usdMoney(3600))
        #expect(receipt.isConsistent)
    }

    @Test func euroReceiptsUseCommaDecimals() {
        var page = Page()
        page.row("CAFE ROMA", height: 0.04)
        page.row("Espresso", "2,50 €")
        page.row("Croissant", "1,90 €")
        page.row("Total", "4,40 €")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.currencyCode == "EUR")
        #expect(receipt.items.map(\.total) == [
            Money(minorUnits: 250, currencyCode: "EUR"),
            Money(minorUnits: 190, currencyCode: "EUR")
        ])
        #expect(receipt.total == Money(minorUnits: 440, currencyCode: "EUR"))
        #expect(receipt.merchant == "Cafe Roma")
    }

    @Test func yenReceiptsHaveNoDecimals() {
        var page = Page()
        page.row("ラーメン屋 Ramen", height: 0.04)
        page.row("Shoyu Ramen", "¥1,200")
        page.row("Gyoza", "¥450")
        page.row("Total", "¥1,650")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.currencyCode == "JPY")
        #expect(receipt.items.map(\.total.minorUnits) == [1200, 450])
        #expect(receipt.total?.minorUnits == 1650)
        #expect(receipt.isConsistent)
    }

    @Test func pricesAreNotTakenFromPhoneNumbersOrDates() {
        var page = Page()
        page.row("Corner Store", height: 0.04)
        page.row("Tel 555-0134")
        page.row("2026-03-14")
        page.row("Gum", "1.25")
        page.row("Total", "1.25")
        let receipt = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(receipt.items.map(\.name) == ["Gum"])
        #expect(receipt.merchant == "Corner Store")
    }

    @Test func datesFollowTheLocaleWhenAmbiguous() {
        var page = Page()
        page.row("Shop", height: 0.04)
        page.row("04/03/2026")
        page.row("Pen", "1.00")
        page.row("Total", "1.00")
        let calendar = Calendar(identifier: .gregorian)
        let us = ReceiptRowParser.parse(lines: page.lines, options: options)
        #expect(calendar.component(.month, from: us.date ?? .distantPast) == 4)
        var british = options
        british.locale = Locale(identifier: "en_GB")
        let gb = ReceiptRowParser.parse(lines: page.lines, options: british)
        #expect(calendar.component(.month, from: gb.date ?? .distantPast) == 3)
    }

    @Test func monthNamesAndFutureDates() {
        var named = Page()
        named.row("Shop", height: 0.04)
        named.row("14 Mar 2026  18:02")
        named.row("Pen", "1.00")
        let parsed = ReceiptRowParser.parse(lines: named.lines, options: options)
        let calendar = Calendar(identifier: .gregorian)
        #expect(calendar.component(.day, from: parsed.date ?? .distantPast) == 14)

        var future = Page()
        future.row("Shop", height: 0.04)
        future.row("01/01/2099")
        #expect(ReceiptRowParser.parse(lines: future.lines, options: options).date == nil)
    }

    @Test func longReceiptsAcrossPagesReadAsOne() {
        var first = Page()
        first.row("Big Store", height: 0.04)
        first.row("Shirt", "20.00")
        var second = Page()
        second.row("Socks", "5.00")
        second.row("Total", "25.00")
        let receipt = ReceiptRowParser.parse(pages: [first.lines, second.lines], options: options)
        #expect(receipt.items.map(\.name) == ["Shirt", "Socks"])
        #expect(receipt.isConsistent)
    }

    @Test func rowBuilderGroupsByHeightAndSortsLeftToRight() {
        let lines = [
            ReceiptTextLine(text: "9.00", boundingBox: CGRect(x: 0.8, y: 0.502, width: 0.1, height: 0.02)),
            ReceiptTextLine(text: "Latte", boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.02)),
            ReceiptTextLine(text: "Total", boundingBox: CGRect(x: 0.1, y: 0.4, width: 0.2, height: 0.02))
        ]
        let rows = ReceiptRowBuilder.rows(from: lines)
        #expect(rows.map(\.text) == ["Latte 9.00", "Total"])
    }

    @Test func priceTokensNeedPrintedDecimals() {
        #expect(ReceiptPrice.minorUnits(of: "12.99", fractionDigits: 2) == 1299)
        #expect(ReceiptPrice.minorUnits(of: "$1,234.50", fractionDigits: 2) == 123_450)
        #expect(ReceiptPrice.minorUnits(of: "(5.00)", fractionDigits: 2) == -500)
        #expect(ReceiptPrice.minorUnits(of: "5.00-", fractionDigits: 2) == -500)
        #expect(ReceiptPrice.minorUnits(of: "12", fractionDigits: 2) == nil)
        #expect(ReceiptPrice.minorUnits(of: "8.5%", fractionDigits: 2) == nil)
        #expect(ReceiptPrice.minorUnits(of: "12x", fractionDigits: 2) == nil)
    }

    @Test func aTotalThatSaysTaxIsIncludedIsTheTotal() {
        for label in ["TOTAL INC GST", "Total incl. VAT", "Total including tax", "Total (GST included)"] {
            let parsed = receipt(["Cafe", "Burger 20.00", "Fries 25.00", "\(label) 45.00"])
            #expect(parsed.total == usdMoney(4500), "\(label)")
            #expect(parsed.tax == nil, "\(label)")
            #expect(parsed.isConsistent, "\(label)")
        }
    }

    @Test func aTotalBeforeTaxIsTheSubtotal() {
        for label in ["Total excl. VAT", "Total before tax"] {
            let parsed = receipt(["Cafe", "Burger 20.00", "Fries 25.00", "\(label) 45.00", "VAT 9.00", "Total 54.00"])
            #expect(parsed.subtotal == usdMoney(4500), "\(label)")
            #expect(parsed.tax == usdMoney(900), "\(label)")
            #expect(parsed.total == usdMoney(5400), "\(label)")
            #expect(parsed.isConsistent, "\(label)")
        }
    }

    @Test func rowsThatNameTheTaxItselfStayTax() {
        for label in ["Total Tax", "Tax Total", "Total Sales Tax", "Sales Tax 8%", "GST included in total", "Total includes GST of"] {
            let parsed = receipt(["Cafe", "Burger 20.00", "Fries 25.00", "\(label) 3.60", "Total 48.60"])
            #expect(parsed.tax == usdMoney(360), "\(label)")
            #expect(parsed.total == usdMoney(4860), "\(label)")
        }
    }
}
