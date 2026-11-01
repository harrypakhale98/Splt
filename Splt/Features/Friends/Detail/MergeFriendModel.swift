import Foundation
import Observation
import SpltCore

/// Chooses who a placeholder really is and merges the two.
@MainActor
@Observable
final class MergeFriendModel {
    let placeholder: Person
    private(set) var suggestions: [Person] = []
    private(set) var others: [Person] = []
    private(set) var didMerge: Person?
    var errorMessage: String?

    @ObservationIgnored private let merger: any PlaceholderMerging

    init(placeholder: Person, services: DataServices, merger: any PlaceholderMerging) {
        self.placeholder = placeholder
        self.merger = merger
        let everyone = ((try? services.people.friends()) ?? []).filter { $0.id != placeholder.id }
        suggestions = DuplicateFinder.candidates(for: placeholder, among: everyone)
        let suggested = Set(suggestions.map(\.id))
        others = everyone.filter { !suggested.contains($0.id) }
    }

    func merge(into target: Person) {
        do {
            try merger.merge(placeholder.id, into: target.id)
            didMerge = target
            errorMessage = nil
        } catch let error as MergeError {
            errorMessage = error.message
        } catch {
            errorMessage = String(localized: "Something went wrong. Please try again.")
        }
    }
}
