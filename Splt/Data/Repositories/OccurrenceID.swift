import CryptoKit
import Foundation
import SpltCore

enum OccurrenceID {
    /// The same expense id for the same template and occurrence on every device.
    static func expenseID(template: UUID, occurrence: Date) -> ExpenseID {
        var input = withUnsafeBytes(of: template.uuid) { Data($0) }
        var seconds = Int64(occurrence.timeIntervalSince1970.rounded()).bigEndian
        input.append(Data(bytes: &seconds, count: MemoryLayout<Int64>.size))
        var bytes = Array(SHA256.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = bytes.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) }
        return ExpenseID(rawValue: UUID(uuid: uuid))
    }
}
