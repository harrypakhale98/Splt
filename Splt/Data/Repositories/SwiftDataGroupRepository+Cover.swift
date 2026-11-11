import Foundation
import SpltCore

/// A photo that could not be read as an image, so it can't become a cover.
struct UnreadablePhotoError: Error, Equatable {}

extension SwiftDataGroupRepository {
    func setCover(_ photo: Data, for id: GroupID) async throws {
        // shrinking a camera photo takes a moment, so it happens off the main actor
        let compressed = await Task.detached(priority: .userInitiated) { PhotoStore.compressed(photo) }.value
        guard let compressed else { throw UnreadablePhotoError() }
        guard let record = try env.groupRecord(id) else { throw DataError.notFound("group \(id)") }
        guard record.kind != .friend else { return }
        let name = try covers.save(compressed)
        let replaced = record.coverFileName
        record.coverFileName = name
        env.tracker.recordEdit(record)
        do {
            try env.save()
        } catch {
            covers.delete(name)
            throw error
        }
        if let replaced, replaced != name { covers.delete(replaced) }
    }

    func removeCover(for id: GroupID) throws {
        guard let record = try env.groupRecord(id), let replaced = record.coverFileName else { return }
        record.coverFileName = nil
        env.tracker.recordEdit(record)
        try env.save()
        covers.delete(replaced)
    }

    func setDefaultSplit(_ split: DefaultSplit?, for id: GroupID) throws {
        guard let record = try env.groupRecord(id) else { throw DataError.notFound("group \(id)") }
        let data = split.map { RecordCoding.encode($0) }
        guard record.defaultSplitData != data else { return }
        record.defaultSplitData = data
        env.tracker.recordEdit(record)
        try env.save()
    }
}
