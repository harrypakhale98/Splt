import Foundation
import ImageIO
import SpltCore
import UIKit

extension ExpenseFormModel {
    // MARK: Describe it

    private static let longestNote = 1_000

    /// Reads the "Describe it" note and fills the form. The model is optional: the rules parser
    /// always answers, so this works without the on-device language model.
    func fillFromNote() async {
        let text = String(describeText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.longestNote))
        guard !text.isEmpty else { return }
        isReading = true
        defer { isReading = false }
        let others = members.filter { $0.id != me?.id }.map(\.name)
        let context = QuickAddContext(candidateNames: others, defaultCurrencyCode: currencyCode)
        let draft = await dependencies.parser.parse(text, context: context)
        guard !Task.isCancelled else { return }
        apply(quickAdd: draft)
    }

    /// Fills the form from pasted text. A bank text or receipt gives the shop and the amount; anything else
    /// is read like a typed description.
    func fill(fromPasted text: String) async {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.longestNote))
        if let payment = PaymentTextParser.parse(trimmed, localCurrency: currencyCode) {
            apply(ExpenseDraft(title: payment.merchant ?? "", total: payment.amount))
            filledNotice = String(localized: "Filled in from the pasted text.")
            return
        }
        describeText = trimmed
        await fillFromNote()
    }

    func apply(quickAdd draft: QuickAddDraft) {
        guard !draft.isEmpty else {
            filledNotice = String(localized: "Nothing to fill in. Try adding an amount and what it was for.")
            unmatchedNames = []
            ambiguousNames = []
            return
        }
        var filled: [String] = []
        if let amount = draft.amount {
            currencyCode = amount.currencyCode
            amountText = AmountInput.text(for: amount, locale: locale)
            filled.append(String(localized: "amount"))
        } else if let hint = draft.currencyHint {
            currencyCode = hint
        }
        if !draft.title.isEmpty {
            title = draft.title
            filled.append(String(localized: "title"))
        }
        if let hint = draft.category {
            category = ExpenseCategory(hint)
            suggestedCategory = nil
            filled.append(String(localized: "category"))
        }

        let resolver = NameResolver(candidates: members.map(\.name))
        func member(_ name: String) -> Person? {
            resolver.matchingCandidate(for: name).flatMap { match in members.first { $0.name == match } }
        }
        var unmatched: [String] = []
        var named: [Person] = []
        for name in draft.participantNames {
            if let person = member(name) { named.append(person) } else { unmatched.append(name) }
        }
        if !named.isEmpty {
            participants = Set(named.map(\.id) + [me?.id].compactMap { $0 })
            filled.append(String(localized: "people"))
        }
        applyPayer(draft.payer, member: member, unmatched: &unmatched, filled: &filled)
        applySplitHint(draft.splitHint, member: member, unmatched: &unmatched, filled: &filled)

        func fitsSeveral(_ name: String) -> Bool {
            members.filter { $0.name.foldedWords.first == name.foldedWords.first }.count > 1
        }
        unmatchedNames = unmatched.filter { !fitsSeveral($0) }
        ambiguousNames = unmatched.filter(fitsSeveral)
        filledNotice = filled.isEmpty ? nil : String(localized: "Filled in \(filled.formatted(.list(type: .and))). Check it above.")
    }

    private func applyPayer(
        _ payerHint: QuickAddPayer?, member: (String) -> Person?, unmatched: inout [String], filled: inout [String]
    ) {
        switch payerHint {
        case .me:
            payer = PayerState()
            payer.single = me?.id
            filled.append(String(localized: "payer"))
        case .person(let name):
            if let person = member(name) {
                payer = PayerState()
                payer.single = person.id
                participants.insert(person.id)
                filled.append(String(localized: "payer"))
            } else if !unmatched.contains(name) {
                unmatched.append(name)
            }
        case nil:
            break
        }
    }

    private func applySplitHint(
        _ hint: QuickAddSplitHint?, member: (String) -> Person?, unmatched: inout [String], filled: inout [String]
    ) {
        switch hint {
        case .equal:
            split.method = .equal
            filled.append(String(localized: "split"))
        case .adjustments(let shares):
            var applied = false
            for share in shares {
                guard let person = member(share.name) else {
                    if !unmatched.contains(share.name) { unmatched.append(share.name) }
                    continue
                }
                participants.insert(person.id)
                split.adjustments[person.id] = AmountInput.text(for: share.amount, locale: locale)
                applied = true
            }
            if applied {
                split.method = .adjustment
                filled.append(String(localized: "split"))
            }
        case .exactAmounts(let shares):
            applyExact(shares, member: member, unmatched: &unmatched, filled: &filled)
        case nil:
            break
        }
    }

    /// The named people owe what the note says; everyone else in the split shares the rest equally.
    private func applyExact(
        _ shares: [QuickAddShare], member: (String) -> Person?, unmatched: inout [String], filled: inout [String]
    ) {
        var fixed: [PersonID: Money] = [:]
        for share in shares {
            if let person = member(share.name) {
                fixed[person.id] = share.amount
                participants.insert(person.id)
            } else if !unmatched.contains(share.name) {
                unmatched.append(share.name)
            }
        }
        guard !fixed.isEmpty else { return }
        split.method = .exact
        for (person, amount) in fixed { split.exact[person] = AmountInput.text(for: amount, locale: locale) }
        let others = participants.subtracting(fixed.keys)
        if let total, !others.isEmpty {
            let left = total.minorUnits - fixed.values.reduce(0) { $0 + $1.minorUnits }
            if let parts = try? LargestRemainderAllocator.allocate(
                total: max(left, 0), weights: Dictionary(uniqueKeysWithValues: others.map { ($0, Int64(1)) })
            ) {
                for (person, units) in parts {
                    split.exact[person] = AmountInput.text(for: Money(minorUnits: units, currencyCode: total.currencyCode), locale: locale)
                }
            }
        }
        filled.append(String(localized: "split"))
    }

    // MARK: Category suggestions

    /// Asks for a category suggestion a moment after the title stops changing.
    func titleDidChange() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        categoryTask?.cancel()
        guard text.count >= 3 else {
            suggestedCategory = nil
            return
        }
        let suggester = dependencies.categories
        categoryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let hint = await suggester.suggest(title: text, merchant: nil)?.category
            guard !Task.isCancelled, let self else { return }
            self.suggestedCategory = hint.map { ExpenseCategory($0) }
        }
    }

    func acceptSuggestedCategory() {
        guard let suggestedCategory else { return }
        category = suggestedCategory
        self.suggestedCategory = nil
    }

    // MARK: Receipts

    /// Scans a photo from the library or the camera and fills the itemized editor. The spinner shows
    /// while the photo is still loading, and a second pick during a scan is ignored.
    func importReceipt(loading load: @escaping @Sendable () async -> Data?) async {
        guard beginScan() else { return }
        defer { isScanning = false }
        guard let data = await load() else {
            scanNotice = String(localized: "That photo could not be loaded.")
            return
        }
        await read(pages: [data], unreadable: String(localized: "That image could not be read."))
    }

    /// Scans a photo given as image data.
    func importReceipt(imageData: Data) async {
        guard beginScan() else { return }
        defer { isScanning = false }
        await read(pages: [imageData], unreadable: String(localized: "That image could not be read."))
    }

    /// Scans the pages of a document camera result, in reading order.
    func importReceipt(pageImages: [UIImage]) async {
        guard beginScan() else { return }
        defer { isScanning = false }
        // encoding full size camera pages takes a while, so it happens away from the main actor
        let pages = await Task.detached(priority: .userInitiated) {
            pageImages.compactMap { $0.jpegData(compressionQuality: 0.9) }
        }.value
        await read(pages: pages, unreadable: String(localized: "That scan could not be read."))
    }

    /// Scans the pages of a document camera result, given as image data in reading order.
    func importReceipt(pages: [Data]) async {
        guard beginScan() else { return }
        defer { isScanning = false }
        await read(pages: pages, unreadable: String(localized: "That scan could not be read."))
    }

    /// Starts a scan, or returns false while one is running so its items are never overwritten.
    private func beginScan() -> Bool {
        guard !isScanning else { return false }
        isScanning = true
        scanNotice = nil
        return true
    }

    private func read(pages: [Data], unreadable: String) async {
        // shrinking, decoding and stitching photos is slow, so none of it runs on the main actor
        let prepared = await Task.detached(priority: .userInitiated) { () -> (pages: [Data], images: [CGImage], photo: Data?) in
            let compressed = pages.compactMap { PhotoStore.compressed($0) }
            let images = compressed.compactMap(Self.cgImage)
            let photo = compressed.count > 1 ? PhotoStore.stitched(compressed) : compressed.first
            return (compressed, images, photo)
        }.value
        guard !prepared.pages.isEmpty else {
            scanNotice = unreadable
            return
        }
        let scanner = dependencies.scanner(currencyCode)
        let parsed = await scanner.scan(prepared.images)
        guard !Task.isCancelled else { return }
        // The items come from every page, so the photo kept with them shows every page too.
        receipt.pendingImage = prepared.photo ?? prepared.pages.first
        apply(receipt: parsed)
    }

    func apply(receipt parsed: ParsedReceipt) {
        let charged = parsed.items.filter { !$0.total.isNegative }
        let lineDiscounts = parsed.items.reduce(Int64(0)) { $0 + max(-$1.total.minorUnits, 0) }
        guard !charged.isEmpty else {
            scanNotice = String(localized: "The receipt is attached, but no items could be read. Add them by hand.")
            return
        }
        if let merchant = parsed.merchant, title.trimmingCharacters(in: .whitespaces).isEmpty { title = merchant }
        var changedDay: Date?
        if let receiptDate = parsed.date {
            if !Calendar.current.isDate(receiptDate, inSameDayAs: date) { changedDay = receiptDate }
            date = receiptDate
        }
        currencyCode = parsed.currencyCode
        split.items = charged.map {
            ItemDraft(name: $0.name, amountText: AmountInput.text(for: $0.total, locale: locale), assignees: [])
        }
        let other = parsed.otherCharges?.minorUnits ?? 0
        let tax = (parsed.tax?.minorUnits ?? 0) + max(other, 0)
        split.taxText = tax == 0 ? "" : AmountInput.text(for: Money(minorUnits: tax, currencyCode: parsed.currencyCode), locale: locale)
        split.tipText = parsed.tip.map { AmountInput.text(for: $0, locale: locale) } ?? ""
        let discount = lineDiscounts + max(-other, 0)
        split.discountText = discount > 0
            ? AmountInput.text(for: Money(minorUnits: discount, currencyCode: parsed.currencyCode), locale: locale) : ""
        split.method = .itemized
        selectedItemID = split.items.first?.id
        let computed = split.itemizedTotal(currencyCode: parsed.currencyCode, locale: locale)
        if let amount = parsed.total ?? computed { amountText = AmountInput.text(for: amount, locale: locale) }
        var notice = parsed.isConsistent
            ? String(localized: "Scanned \(charged.count) items. Tap people under each item to assign it.")
            : String(localized: "Scanned \(charged.count) items. The numbers do not fully add up, so check them against the receipt.")
        // the date moves quietly otherwise, and a misread one would file the expense on the wrong day
        if let changedDay {
            let day = changedDay.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
            notice += " " + String(localized: "The date is now \(day), from the receipt.")
        }
        scanNotice = notice
    }

    nonisolated private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
