import SpltCore

extension SplitGroup {
    init(_ record: GroupRecord) {
        self.init(
            id: record.groupID, name: record.name, symbol: record.symbol, currencyCode: record.currencyCode,
            kind: record.kind, memberIDs: record.memberIDs.map { PersonID(rawValue: $0) },
            simplifiesDebts: record.simplifiesDebts, isArchived: record.isArchived,
            tripStart: record.tripStart, tripEnd: record.tripEnd,
            pinnedRate: record.pinnedRateData.flatMap { try? RecordCoding.decode(PinnedRate.self, from: $0) },
            coverFileName: record.coverFileName,
            defaultSplit: record.defaultSplitData.flatMap { try? RecordCoding.decode(DefaultSplit.self, from: $0) },
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
        coverFileName = group.coverFileName
        defaultSplitData = group.defaultSplit.map { RecordCoding.encode($0) }
    }

    /// Copies the edited fields. The cover photo and the default split are left alone: they have
    /// their own repository methods, so an older copy of the group never puts back a replaced photo.
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
