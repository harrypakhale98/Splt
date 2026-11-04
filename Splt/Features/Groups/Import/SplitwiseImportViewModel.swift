import Foundation
import Observation
import SpltCore

/// Who a Splitwise member becomes in Splt.
struct MemberMapping: Identifiable, Equatable, Sendable {
    enum Choice: Hashable, Sendable {
        case newPerson
        case existing(PersonID)
    }

    var name: String
    var choice: Choice

    var id: String { name }
}

/// What the file holds, for the preview step.
struct SplitwiseImportPreview: Equatable, Sendable {
    var expenseCount: Int
    var paymentCount: Int
    /// What was spent, one amount per currency.
    var totals: [Money]
    /// Rows that cannot be imported, with the reason.
    var warnings: [ImportWarning]
}

/// The steps of importing a Splitwise export: read the file, preview it, match people, import.
/// Nothing is written until `performImport()`, and a failed import removes what it started.
@MainActor
@Observable
final class SplitwiseImportViewModel {
    enum Step {
        case instructions
        case preview
    }

    private(set) var step: Step = .instructions
    var groupName = ""
    var currencyCode: String
    var errorMessage: String?
    private(set) var mappings: [MemberMapping] = []
    private(set) var preview: SplitwiseImportPreview?
    /// Set when this exact file was imported before and that group still exists.
    private(set) var existingGroupID: GroupID?
    private(set) var isImporting = false
    /// You first, then everyone else by name.
    private(set) var candidates: [Person] = []

    @ObservationIgnored private let groups: any GroupRepository
    @ObservationIgnored private let people: any PersonRepository
    @ObservationIgnored private let history: SplitwiseImportHistory
    @ObservationIgnored private var text = ""
    @ObservationIgnored private var fingerprint = ""

    init(services: DataServices, history: SplitwiseImportHistory = SplitwiseImportHistory(), defaultCurrencyCode: String) {
        groups = services.groups
        people = services.people
        self.history = history
        currencyCode = defaultCurrencyCode
    }

    // MARK: Reading the file

    /// Reads the file at `url` and moves to the preview. Returns false and sets `errorMessage` when it cannot.
    @discardableResult
    func loadFile(at url: URL) -> Bool {
        do {
            return load(text: try SplitwiseFile.read(url), fileName: url.lastPathComponent)
        } catch {
            errorMessage = String(localized: "Splt couldn't open that file. Choose a CSV exported from Splitwise.")
            return false
        }
    }

    @discardableResult
    func load(text raw: String, fileName: String) -> Bool {
        let cleaned = SplitwiseFile.normalized(raw)
        do {
            let parsed = try SplitwiseCSVImporter.parse(cleaned, groupID: GroupID())
            guard !parsed.expenses.isEmpty || !parsed.payments.isEmpty else {
                errorMessage = String(localized: "The file has no expenses or payments that Splt can import.")
                return false
            }
            candidates = sortedCandidates()
            text = cleaned
            fingerprint = SplitwiseFile.fingerprint(cleaned)
            groupName = SplitwiseFile.groupName(fromFileName: fileName)
            currencyCode = Self.commonCurrency(in: parsed) ?? currencyCode
            mappings = parsed.memberNames.map { MemberMapping(name: $0, choice: autoChoice(for: $0)) }
            preview = SplitwiseImportPreview(
                expenseCount: parsed.expenses.count,
                paymentCount: parsed.payments.count,
                totals: MoneyTotals.sum(parsed.expenses.map(\.total)),
                warnings: parsed.warnings
            )
            existingGroupID = history.groupID(forFingerprint: fingerprint).flatMap { id in
                (try? groups.group(id: id)) == nil ? nil : id
            }
            errorMessage = nil
            step = .preview
            return true
        } catch {
            errorMessage = GroupErrorMessage.text(for: error)
            return false
        }
    }

    /// Goes back to choosing a file. Nothing has been written yet.
    func chooseAnotherFile() {
        step = .instructions
        preview = nil
        existingGroupID = nil
        mappings = []
    }

    private static func commonCurrency(in parsed: SplitwiseImport) -> String? {
        let codes = parsed.expenses.map(\.total.currencyCode) + parsed.payments.map(\.amount.currencyCode)
        let counts = Dictionary(codes.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }?.key
    }

    // MARK: Matching people

    private func sortedCandidates() -> [Person] {
        let everyone = (try? people.allPeople()) ?? []
        return everyone.filter(\.isMe) + everyone.filter { !$0.isMe }
    }

    private func autoChoice(for name: String) -> MemberMapping.Choice {
        let match = candidates.first { Self.sameName($0.name, name) }
        return match.map { .existing($0.id) } ?? .newPerson
    }

    func setChoice(_ choice: MemberMapping.Choice, for name: String) {
        guard let index = mappings.firstIndex(where: { $0.name == name }) else { return }
        mappings[index].choice = choice
    }

    func choice(for name: String) -> MemberMapping.Choice {
        mappings.first { $0.name == name }?.choice ?? .newPerson
    }

    func person(_ id: PersonID) -> Person? {
        candidates.first { $0.id == id }
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(rhs.trimmingCharacters(in: .whitespacesAndNewlines), options: [.caseInsensitive, .diacriticInsensitive])
            == .orderedSame
    }

    /// Why the current matches cannot be imported, or nil when they are fine.
    var mappingProblem: String? {
        var seen: [PersonID: String] = [:]
        for mapping in mappings {
            guard case .existing(let id) = mapping.choice else { continue }
            if let other = seen[id], let person = person(id) {
                let name = person.name
                return String(localized: "\(name) is matched to both \(other) and \(mapping.name). Match each person once.")
            }
            seen[id] = mapping.name
        }
        var members = candidates.filter(\.isMe)
        for mapping in mappings {
            if case .existing(let id) = mapping.choice, let person = person(id), !person.isMe { members.append(person) }
        }
        for (index, person) in members.enumerated() {
            if let twin = members[..<index].first(where: { Self.sameName($0.name, person.name) }) {
                let name = twin.name
                return String(localized: "Two people in the group are named \(name). Rename one of them first.")
            }
        }
        return nil
    }

    var canImport: Bool {
        preview != nil && existingGroupID == nil && mappingProblem == nil && !isImporting
            && !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Importing

    /// Creates the group and imports into it, then returns the group. On any failure the group is
    /// removed again and nothing is left behind.
    func performImport() -> GroupID? {
        guard canImport else { return nil }
        isImporting = true
        defer { isImporting = false }

        var created: GroupID?
        do {
            let me = try people.me() ?? people.ensureMe(name: String(localized: "You"))
            var memberIDs = [me.id]
            for mapping in mappings {
                if case .existing(let id) = mapping.choice, !memberIDs.contains(id) { memberIDs.append(id) }
            }
            guard let renamed = SplitwiseFile.renamingMembers(in: text, to: resolvedNames(me: me)) else {
                throw DataError.unreadableCSV("The header could not be read.")
            }
            let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = SplitGroup(
                name: name,
                symbol: GroupSymbolSuggester.symbol(for: name) ?? GroupTemplate.standard.defaultSymbol,
                currencyCode: currencyCode,
                memberIDs: memberIDs
            )
            try groups.create(group)
            created = group.id
            let summary = try groups.importSplitwiseCSV(renamed, into: group.id)
            guard summary.expensesAdded + summary.paymentsAdded > 0 else {
                throw DataError.unreadableCSV("Nothing in the file could be imported.")
            }
            history.record(fingerprint: fingerprint, groupID: group.id)
            existingGroupID = group.id
            return group.id
        } catch {
            if let created { try? groups.delete(id: created) }
            errorMessage = GroupErrorMessage.text(for: error)
            return nil
        }
    }

    /// The name each Splitwise member gets in the file handed to the importer. Matched people keep
    /// their own names. New people keep the Splitwise name unless it would be taken for someone in the group.
    func resolvedNames(me: Person) -> [String: String] {
        var used: Set<String> = [Self.key(me.name)]
        var result: [String: String] = [:]
        for mapping in mappings {
            if case .existing(let id) = mapping.choice, let person = person(id) {
                result[mapping.name] = person.name
                used.insert(Self.key(person.name))
            }
        }
        for mapping in mappings where mapping.choice == .newPerson {
            var candidate = mapping.name
            var attempt = 1
            while used.contains(Self.key(candidate)) {
                attempt += 1
                candidate = attempt == 2 ? "\(mapping.name) (Splitwise)" : "\(mapping.name) (Splitwise \(attempt - 1))"
            }
            used.insert(Self.key(candidate))
            result[mapping.name] = candidate
        }
        return result
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
