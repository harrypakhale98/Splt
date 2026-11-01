import SpltCore

extension SplitGroup {
    init(_ record: GroupRecord) {
        self.init(
            id: record.groupID, name: record.name, symbol: record.symbol, currencyCode: record.currencyCode,
            kind: record.kind, memberIDs: record.memberIDs.map { PersonID(rawValue: $0) },
            simplifiesDebts: record.simplifiesDebts, isArchived: record.isArchived,
            tripStart: record.tripStart, tripEnd: record.tripEnd,
            pinnedRate: record.pinnedRateData.flatMap { try? RecordCoding.decode(PinnedRate.self, from: $0) },
            createdAt: record.createdAt
        )
    }
}

extension GroupRecord {
    convenience init(_ group: SplitGroup) {
        self.init(
            id: group.id.rawValue, name: group.name, symbol: group.symbol, currencyCode: group.currencyCode,
            kind: group.kind, memberIDs: group.memberIDs.map(\.rawValue),
            simplifiesDebts: group.simplifiesDebts, isArchived: group.isArchived,
            tripStart: group.tripStart, tripEnd: group.tripEnd,
            pinnedRateData: group.pinnedRate.map { RecordCoding.encode($0) },
            createdAt: group.createdAt
        )
    }

    func update(from group: SplitGroup) {
        name = group.name
        symbol = group.symbol
        currencyCode = group.currencyCode
        kind = group.kind
        memberIDs = group.memberIDs.map(\.rawValue)
        simplifiesDebts = group.simplifiesDebts
        isArchived = group.isArchived
        tripStart = group.tripStart
        tripEnd = group.tripEnd
        pinnedRateData = group.pinnedRate.map { RecordCoding.encode($0) }
    }
}
