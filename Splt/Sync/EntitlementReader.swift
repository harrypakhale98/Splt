import Foundation

/// The entitlements an app was signed with, read from its own executable.
///
/// Creating a `CKContainer` without the iCloud entitlement traps, and there is no public call
/// to ask for entitlements, so this reads them from the code signature in the Mach-O file.
struct Entitlements: Equatable, Sendable {
    var values: [String: PlistValue]

    /// The CloudKit container identifiers the app may use.
    var cloudKitContainers: [String] {
        guard hasCloudKitService, case .strings(let identifiers)? = values["com.apple.developer.icloud-container-identifiers"] else {
            return []
        }
        return identifiers
    }

    var hasCloudKitService: Bool {
        guard case .strings(let services)? = values["com.apple.developer.icloud-services"] else { return false }
        return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
    }

    static let none = Entitlements(values: [:])
}

/// The few plist shapes the entitlement check needs.
enum PlistValue: Equatable, Sendable {
    case strings([String])
    case string(String)
    case bool(Bool)
    case other
}

enum EntitlementReader {
    /// Entitlements of the running app, or `none` when it is unsigned or cannot be read.
    static func current() -> Entitlements {
        guard let url = Bundle.main.executableURL,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return .none
        }
        return entitlements(inExecutable: data)
    }

    static func entitlements(inExecutable data: Data) -> Entitlements {
        guard let xml = entitlementsPlist(in: data),
              let object = try? PropertyListSerialization.propertyList(from: xml, format: nil),
              let dictionary = object as? [String: Any] else {
            return .none
        }
        return Entitlements(values: dictionary.mapValues(PlistValue.init))
    }

    private static let fatMagic: UInt32 = 0xcafe_babe
    private static let machO64Magic: UInt32 = 0xfeed_facf
    private static let codeSignatureCommand: UInt32 = 0x1d
    private static let superBlobMagic: UInt32 = 0xfade_0cc0
    private static let entitlementsBlobMagic: UInt32 = 0xfade_7171
    private static let arm64CPUType: UInt32 = 0x0100_000c

    private static func entitlementsPlist(in data: Data) -> Data? {
        guard let slice = firstSlice(of: data), slice.count >= 32,
              slice.readLittle(at: 0) == machO64Magic,
              let commandCount = slice.readLittle(at: 16) else {
            return nil
        }
        var offset = 32
        for _ in 0..<commandCount {
            guard let command = slice.readLittle(at: offset), let size = slice.readLittle(at: offset + 4), size >= 8 else {
                return nil
            }
            if command == codeSignatureCommand,
               let dataOffset = slice.readLittle(at: offset + 8),
               let dataSize = slice.readLittle(at: offset + 12) {
                return entitlementsBlob(in: slice, signatureOffset: Int(dataOffset), signatureSize: Int(dataSize))
            }
            offset += Int(size)
        }
        return nil
    }

    private static func firstSlice(of data: Data) -> Data? {
        guard data.count >= 8 else { return nil }
        if data.readBig(at: 0) == fatMagic {
            guard let count = data.readBig(at: 4) else { return nil }
            var chosen: Data?
            for index in 0..<Int(min(count, 8)) {
                let entry = 8 + index * 20
                guard let cpu = data.readBig(at: entry), let start = data.readBig(at: entry + 8),
                      let size = data.readBig(at: entry + 12),
                      Int(start) + Int(size) <= data.count else { continue }
                let slice = data.subdata(in: Int(start)..<Int(start) + Int(size))
                if cpu == arm64CPUType { return slice }
                chosen = chosen ?? slice
            }
            return chosen
        }
        return data
    }

    private static func entitlementsBlob(in slice: Data, signatureOffset: Int, signatureSize: Int) -> Data? {
        guard signatureOffset >= 0, signatureOffset + signatureSize <= slice.count,
              slice.readBig(at: signatureOffset) == superBlobMagic,
              let count = slice.readBig(at: signatureOffset + 8), count < 64 else {
            return nil
        }
        for index in 0..<Int(count) {
            let entry = signatureOffset + 12 + index * 8
            guard let blobOffset = slice.readBig(at: entry + 4) else { return nil }
            let start = signatureOffset + Int(blobOffset)
            guard slice.readBig(at: start) == entitlementsBlobMagic, let length = slice.readBig(at: start + 4),
                  length >= 8, start + Int(length) <= slice.count else {
                continue
            }
            return slice.subdata(in: start + 8..<start + Int(length))
        }
        return nil
    }
}

extension PlistValue {
    fileprivate init(_ object: Any) {
        switch object {
        case let list as [String]: self = .strings(list)
        case let text as String: self = .string(text)
        case let flag as Bool: self = .bool(flag)
        default: self = .other
        }
    }
}

extension Data {
    fileprivate func readBig(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    fileprivate func readLittle(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }
}
