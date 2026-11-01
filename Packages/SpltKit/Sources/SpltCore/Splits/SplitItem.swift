import Foundation

/// One line of an itemized bill, shared equally by the people it is assigned to.
public struct SplitItem: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var amount: Money
    public var assignees: Set<PersonID>

    public init(id: UUID = UUID(), name: String, amount: Money, assignees: Set<PersonID>) {
        self.id = id
        self.name = name
        self.amount = amount
        self.assignees = assignees
    }
}
