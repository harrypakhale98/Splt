import Foundation
import SpltCore

extension ExpenseFormModel {
    // MARK: What the bar shows

    /// The people drawn on the bar: everyone in the split, or for an itemized bill everyone with an item.
    var barPeople: [Person] {
        if split.method == .itemized {
            let withItems = Set(split.items.flatMap(\.assignees))
            return members.filter { withItems.contains($0.id) }
        }
        return participantList
    }

    private var minorUnitsPerUnit: Int64 { Currency.minorUnitScale(for: currencyCode) }

    /// The segment weights as basis points of the whole bar, whatever the method.
    func barFractions() -> [Int64] {
        let people = barPeople
        guard !people.isEmpty else { return [] }
        let raw: [Int64]
        switch split.method {
        case .equal:
            raw = Array(repeating: 1, count: people.count)
        case .percentage:
            raw = people.map { AmountInput.basisPoints(split.percent[$0.id, default: ""], locale: locale) ?? 0 }
        case .exact:
            raw = people.map { AmountInput.money(split.exact[$0.id, default: ""], currencyCode: currencyCode, locale: locale)?.minorUnits ?? 0 }
        case .shares:
            raw = people.map { AmountInput.hundredths(split.weights[$0.id, default: "1"], locale: locale) ?? 0 }
        case .adjustment, .itemized:
            let byPerson = Dictionary(uniqueKeysWithValues: sharePreview.map { ($0.person.id, max($0.amount.minorUnits, 0)) })
            raw = people.map { byPerson[$0.id] ?? 0 }
        }
        return SplitBarMath.scaled(raw, to: SplitBarMath.basisPoints)
    }

    /// The data for the bar, or nil when nobody is in the split yet.
    var barData: SplitBarData? {
        let people = barPeople
        guard !people.isEmpty else { return nil }
        let total = self.total.flatMap { $0.isZero ? nil : $0 }
        let method = split.method

        var weights: [Int64]
        var scale: Int64
        switch method {
        case .exact, .adjustment:
            if let total, total.minorUnits > 0 {
                scale = total.minorUnits
                weights = SplitBarMath.scaled(barFractions(), to: scale)
            } else {
                scale = SplitBarMath.basisPoints
                weights = barFractions()
            }
        case .shares:
            weights = people.map { shareWholeWeight(for: $0.id) }
            scale = weights.reduce(0, +)
        default:
            scale = SplitBarMath.basisPoints
            weights = barFractions()
        }

        var amounts: [Money]?
        if let total {
            if method == .exact, total.minorUnits > 0 {
                amounts = weights.map { Money(minorUnits: $0, currencyCode: total.currencyCode) }
            } else {
                amounts = SplitBarMath.amounts(for: method == .shares ? weights : barFractions(), total: total)
            }
        }
        let segments = people.indices.map {
            SplitBarSegment(person: people[$0], weight: weights[$0], amount: amounts?[$0])
        }
        return SplitBarData(
            method: method, segments: segments, scale: scale, total: total,
            canDrag: method != .itemized && people.count > 1 && total != nil
        )
    }

    /// A person's share count as a whole number. Fractions scale every count by 100 first.
    private func shareWholeWeight(for id: PersonID) -> Int64 {
        let all = participantList.map { AmountInput.hundredths(split.weights[$0.id, default: "1"], locale: locale) ?? 0 }
        let scale: Int64 = all.allSatisfy { $0 % 100 == 0 } ? 100 : 1
        return max((AmountInput.hundredths(split.weights[id, default: "1"], locale: locale) ?? 0) / scale, 0)
    }

    // MARK: Dragging

    /// Moves a divider to `fraction` of the bar width (0 to 1). `thresholdBasisPoints` is how close
    /// a divider must be to a detent to snap to it. Returns what happened, for haptics.
    @discardableResult
    func dragDivider(_ divider: Int, toFraction fraction: Double, thresholdBasisPoints: Int64 = 150) -> SplitBarDrag? {
        guard let data = barData, data.canDrag else { return nil }
        if split.method == .equal { selectMethod(.percentage) }
        let fraction = min(max(fraction, 0), 1)
        let count = data.segments.count

        switch split.method {
        case .shares:
            let result = SplitBarMath.dragShares(divider: divider, toFraction: fraction, weights: data.weights)
            if result.didChange { writeShares(result.weights, for: data.segments) }
            return result
        case .percentage:
            let weights = barFractions()
            let scale = SplitBarMath.basisPoints
            let result = run(
                divider: divider, fraction: fraction, weights: weights, scale: scale, count: count,
                total: nil, freeStep: 100, thresholdBasisPoints: thresholdBasisPoints
            )
            if result.didChange { writePercent(result.weights, for: data.segments) }
            return result
        case .exact, .adjustment:
            guard let total = data.total, total.minorUnits > 0 else { return nil }
            let unit = minorUnitsPerUnit
            let freeStep = total.minorUnits >= unit * 20 ? unit : 1
            let result = run(
                divider: divider, fraction: fraction, weights: data.weights, scale: data.scale, count: count,
                total: total, freeStep: freeStep, thresholdBasisPoints: thresholdBasisPoints
            )
            if result.didChange {
                if split.method == .exact {
                    writeExact(result.weights, for: data.segments)
                } else {
                    writeAdjustments(result.weights, for: data.segments)
                }
            }
            return result
        default:
            return nil
        }
    }

    private func run(
        divider: Int, fraction: Double, weights: [Int64], scale: Int64, count: Int,
        total: Money?, freeStep: Int64, thresholdBasisPoints: Int64
    ) -> SplitBarDrag {
        let threshold = max(scale * thresholdBasisPoints / SplitBarMath.basisPoints, 1)
        let prefix = weights.indices.contains(divider) ? weights[..<divider].reduce(0, +) : 0
        let detents = SplitBarMath.detents(
            divider: divider, count: count, scale: scale, prefix: prefix,
            totalMinor: total?.minorUnits, unitMinor: minorUnitsPerUnit,
            spaceIsMinorUnits: total != nil, threshold: threshold
        )
        let raw = Int64((fraction * Double(scale)).rounded())
        return SplitBarMath.drag(
            divider: divider, to: raw, weights: weights, detents: detents, freeStep: freeStep,
            minimum: SplitBarMath.minimumSegment(count: count, scale: scale), threshold: threshold
        )
    }

    // MARK: Writing back

    private func writePercent(_ weights: [Int64], for segments: [SplitBarSegment]) {
        for (segment, weight) in zip(segments, weights) {
            split.percent[segment.id] = AmountInput.hundredthsText(weight, locale: locale)
        }
    }

    private func writeExact(_ weights: [Int64], for segments: [SplitBarSegment]) {
        for (segment, weight) in zip(segments, weights) {
            split.exact[segment.id] = AmountInput.text(for: Money(minorUnits: weight, currencyCode: currencyCode), locale: locale)
        }
    }

    /// What an equal split gives each person, from the calculator itself so spare cents match.
    private func calculatorEqualShares(for people: [PersonID], total: Money) -> [Int64]? {
        guard let result = try? SplitCalculator.calculate(.equal(participants: Set(people)), total: total) else { return nil }
        return people.map { result.share(for: $0).minorUnits }
    }

    private func writeAdjustments(_ shares: [Int64], for segments: [SplitBarSegment]) {
        let equal = total.flatMap { calculatorEqualShares(for: segments.map(\.id), total: $0) }
        for (segment, value) in zip(segments, SplitBarMath.adjustments(for: shares, equal: equal)) {
            split.adjustments[segment.id] = value == 0 ? "" : AmountInput.text(for: Money(minorUnits: value, currencyCode: currencyCode), locale: locale)
        }
    }

    private func writeShares(_ weights: [Int64], for segments: [SplitBarSegment]) {
        for (segment, weight) in zip(segments, weights) {
            split.weights[segment.id] = String(weight)
        }
    }

    // MARK: Switching the model

    /// Switches the split method and carries the current split over, so the bar keeps its shape.
    func selectMethod(_ method: SplitMethod) {
        let previous = split.method
        guard method != previous else { return }
        let fractions = barFractions()
        let people = barPeople
        let converts = previous != .itemized && fractions.count == people.count && !people.isEmpty
        let preview = Dictionary(uniqueKeysWithValues: sharePreview.map { ($0.person.id, $0.amount.minorUnits) })
        let currentShares: [Int64]? = people.allSatisfy({ preview[$0.id] != nil }) ? people.map { preview[$0.id] ?? 0 } : nil

        if converts {
            switch method {
            case .percentage:
                for (person, weight) in zip(people, fractions) {
                    split.percent[person.id] = AmountInput.hundredthsText(weight, locale: locale)
                }
            case .exact:
                if let total, total.minorUnits > 0 {
                    let minors = currentShares ?? SplitBarMath.amounts(for: fractions, total: total).map(\.minorUnits)
                    for (person, units) in zip(people, minors) {
                        split.exact[person.id] = AmountInput.text(for: Money(minorUnits: units, currencyCode: currencyCode), locale: locale)
                    }
                }
            case .adjustment:
                if let total, total.minorUnits > 0 {
                    let minors = currentShares ?? SplitBarMath.amounts(for: fractions, total: total).map(\.minorUnits)
                    let equal = calculatorEqualShares(for: people.map(\.id), total: total)
                    for (person, value) in zip(people, SplitBarMath.adjustments(for: minors, equal: equal)) {
                        split.adjustments[person.id] = value == 0 ? "" : AmountInput.text(for: Money(minorUnits: value, currencyCode: currencyCode), locale: locale)
                    }
                }
            case .shares:
                let wanted = SplitBarMath.scaled(fractions, to: Int64(people.count) * 4)
                let divisor = wanted.reduce(0) { Self.gcd($0, max($1, 1)) }
                for (person, weight) in zip(people, wanted) {
                    split.weights[person.id] = String(max(weight, 1) / max(divisor, 1))
                }
            case .equal, .itemized:
                break
            }
        }
        split.method = method
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var (x, y) = (abs(a), abs(b))
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }

    // MARK: Fine tuning and VoiceOver

    /// One step for the stepper and for VoiceOver: 1 percent, 1 share, or one currency unit.
    @discardableResult
    func adjustShare(of person: PersonID, increase: Bool) -> Bool {
        guard let data = barData, let index = data.segments.firstIndex(where: { $0.id == person }),
              data.segments.count > 1 else { return false }
        if split.method == .equal { selectMethod(.percentage) }
        guard let current = barData else { return false }
        let sign: Int64 = increase ? 1 : -1

        switch split.method {
        case .shares:
            var weights = current.weights
            weights[index] = max(weights[index] + sign, 1)
            guard weights != current.weights else { return false }
            writeShares(weights, for: current.segments)
            return true
        case .percentage:
            let weights = SplitBarMath.nudge(
                index: index, by: sign * 100, weights: barFractions(),
                minimum: SplitBarMath.minimumSegment(count: current.segments.count, scale: SplitBarMath.basisPoints)
            )
            guard weights != barFractions() else { return false }
            writePercent(weights, for: current.segments)
            return true
        case .exact, .adjustment:
            guard let total = current.total, total.minorUnits > 0 else { return false }
            let unit = minorUnitsPerUnit
            let step = total.minorUnits >= unit * 20 ? unit : 1
            let weights = SplitBarMath.nudge(
                index: index, by: sign * step, weights: current.weights,
                minimum: SplitBarMath.minimumSegment(count: current.segments.count, scale: current.scale)
            )
            guard weights != current.weights else { return false }
            if split.method == .exact { writeExact(weights, for: current.segments) } else { writeAdjustments(weights, for: current.segments) }
            return true
        default:
            return false
        }
    }

    /// What one VoiceOver step changes, spoken in the hint.
    var barStepDescription: String {
        switch split.method {
        case .shares: String(localized: "One share")
        case .percentage, .equal: String(localized: "One percent")
        case .exact, .adjustment: String(localized: "One \(currencyCode) unit")
        case .itemized: ""
        }
    }

    // MARK: Who's in

    /// Tapping a person chip: includes or removes them, or assigns the selected receipt item.
    func tapPerson(_ id: PersonID) {
        if let item = selectedItemID, split.method == .itemized {
            assign(id, to: item)
        } else {
            toggleParticipant(id)
        }
    }

    func selectEveryone() {
        participants = Set(members.map(\.id))
    }

    func isPayer(_ id: PersonID) -> Bool {
        payer.isMultiple ? payer.selected.contains(id) : payer.single == id
    }

    /// Long press "Paid by": this person alone paid.
    func makeSolePayer(_ id: PersonID) {
        payer = PayerState()
        payer.single = id
        payersFollowAmount = false
    }

    /// Long press "Also paid": adds or removes a second payer, dividing the payments evenly.
    func toggleAlsoPaid(_ id: PersonID) {
        if !payer.isMultiple {
            guard payer.single != id else { return }
            let first = payer.single ?? me?.id
            payer.isMultiple = true
            payer.selected = Set([first, id].compactMap { $0 })
        } else if payer.selected.contains(id) {
            payer.selected.remove(id)
        } else {
            payer.selected.insert(id)
        }
        if payer.selected.count <= 1 {
            let remaining = payer.selected.first ?? payer.single
            payer = PayerState()
            payer.single = remaining
            payersFollowAmount = false
        } else {
            payersFollowAmount = true
            splitPaymentsEvenly()
        }
    }

    /// Keeps evenly divided payments in step with the amount as it is typed.
    func refollowPayments() {
        guard payersFollowAmount, payer.isMultiple else { return }
        splitPaymentsEvenly()
    }

    /// "You paid 60.00, split 3 ways": the line above the Save button.
    var summaryLine: String {
        guard let total, !total.isZero else { return String(localized: "Enter an amount to get started.") }
        let amount = MoneyFormatting.magnitudeString(total, locale: locale)
        let who: String
        if payer.isMultiple {
            who = String(localized: "\(payer.selected.count) people paid \(amount)")
        } else if let single = payer.single {
            who = single == me?.id ? String(localized: "You paid \(amount)") : String(localized: "\(displayName(for: single)) paid \(amount)")
        } else {
            who = amount
        }
        let people = barPeople.count
        let how: String
        switch split.method {
        case .equal: how = String(localized: "split \(people) ways")
        case .percentage: how = String(localized: "split by percent")
        case .exact: how = String(localized: "split by amount")
        case .shares: how = String(localized: "split by shares")
        case .adjustment: how = String(localized: "split with adjustments")
        case .itemized: how = String(localized: "split by item")
        }
        return "\(who), \(how)"
    }
}
