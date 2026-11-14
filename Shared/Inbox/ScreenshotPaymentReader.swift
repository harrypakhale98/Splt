import CoreGraphics
import Foundation
import SpltCore
import Vision

/// Reads a payment from a screenshot of Wallet, a bank app or a receipt. Everything stays on the device,
/// and the person checks what it found before it is kept.
enum ScreenshotPaymentReader {
    struct Reading: Equatable, Sendable {
        var merchant: String?
        var amount: Money?
    }

    static func read(_ image: CGImage, localCurrency: String = PaymentAmount.localCurrencyCode) async -> Reading {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        let observations = (try? await request.perform(on: image)) ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return reading(from: lines, localCurrency: localCurrency)
    }

    /// The amount on a "total" line when there is one, otherwise the largest amount shown.
    /// The merchant is the first line of words that isn't screen furniture, a time or an amount.
    static func reading(from lines: [String], localCurrency: String = PaymentAmount.localCurrencyCode) -> Reading {
        let totalWords = ["total", "amount", "paid", "charged", "grand"]
        let priced = lines.map { (line: $0, amounts: PaymentTextParser.amounts(in: $0, localCurrency: localCurrency)) }
        let totalLine = priced.last { entry in
            !entry.amounts.isEmpty && totalWords.contains { entry.line.lowercased().contains($0) }
        }
        let amount = totalLine?.amounts.last ?? priced.flatMap(\.amounts).max { $0.minorUnits < $1.minorUnits }
        let chrome = [
            "wallet", "transactions", "latest", "done", "back", "apple pay", "pending", "card balance",
            "details", "receipt", "today", "yesterday", "total", "amount", "status", "approved", "search"
        ]
        let merchant = priced.first { entry in
            let lower = entry.line.lowercased().trimmingCharacters(in: .whitespaces)
            return entry.amounts.isEmpty && entry.line.filter(\.isLetter).count >= 2
                && !chrome.contains { lower == $0 || lower.hasPrefix($0 + " ") }
                && lower.range(of: "^[0-9]{1,2}[:.][0-9]{2}", options: .regularExpression) == nil
        }?.line.trimmingCharacters(in: .whitespaces)
        return Reading(merchant: merchant.map { String($0.prefix(60)) }, amount: amount)
    }
}
