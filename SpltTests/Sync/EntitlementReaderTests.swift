import Foundation
import Testing
@testable import Splt

@Suite("Entitlement reader")
struct EntitlementReaderTests {
    private static func be(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }

    private static func le(_ value: UInt32) -> [UInt8] {
        be(value).reversed()
    }

    private static func plist(_ values: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    /// A minimal 64 bit Mach-O with one load command, the code signature.
    private static func machO(entitlementsXML: Data?) -> Data {
        var signature: [UInt8] = []
        if let xml = entitlementsXML {
            let blob = be(0xfade_7171) + be(UInt32(8 + xml.count)) + [UInt8](xml)
            let superBlobLength = 12 + 8 + blob.count
            signature = be(0xfade_0cc0) + be(UInt32(superBlobLength)) + be(1) + be(5) + be(20) + blob
        } else {
            signature = be(0xfade_0cc0) + be(12) + be(0)
        }
        let header = le(0xfeed_facf) + le(0x0100_000c) + le(0) + le(2) + le(1) + le(16) + le(0) + le(0)
        let command = le(0x1d) + le(16) + le(48) + le(UInt32(signature.count))
        return Data(header + command + signature)
    }

    @Test func readsCloudKitContainersFromTheSignature() throws {
        let xml = try Self.plist([
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.example.app"],
            "com.apple.developer.icloud-services": ["CloudKit"],
            "aps-environment": "development",
        ])
        let entitlements = EntitlementReader.entitlements(inExecutable: Self.machO(entitlementsXML: xml))
        #expect(entitlements.cloudKitContainers == ["iCloud.com.example.app"])
        #expect(entitlements.hasCloudKitService)
        #expect(entitlements.values["aps-environment"] == .string("development"))
    }

    @Test func unsignedExecutableHasNoEntitlements() {
        let entitlements = EntitlementReader.entitlements(inExecutable: Self.machO(entitlementsXML: nil))
        #expect(entitlements == .none)
        #expect(entitlements.cloudKitContainers.isEmpty)
    }

    @Test func containersWithoutTheCloudKitServiceAreIgnored() throws {
        let xml = try Self.plist([
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.example.app"],
            "com.apple.developer.icloud-services": ["CloudDocuments"],
        ])
        let entitlements = EntitlementReader.entitlements(inExecutable: Self.machO(entitlementsXML: xml))
        #expect(entitlements.cloudKitContainers.isEmpty)
    }

    @Test func readsTheArm64SliceOfAUniversalBinary() throws {
        let xml = try Self.plist([
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.example.fat"],
            "com.apple.developer.icloud-services": ["CloudKit"],
        ])
        let other = Self.machO(entitlementsXML: nil)
        let arm = Self.machO(entitlementsXML: xml)
        let firstOffset: UInt32 = 64
        let secondOffset = firstOffset + UInt32(other.count)
        var fat = Self.be(0xcafe_babe) + Self.be(2)
        fat += Self.be(0x0100_0007) + Self.be(3) + Self.be(firstOffset) + Self.be(UInt32(other.count)) + Self.be(0)
        fat += Self.be(0x0100_000c) + Self.be(0) + Self.be(secondOffset) + Self.be(UInt32(arm.count)) + Self.be(0)
        fat += [UInt8](repeating: 0, count: Int(firstOffset) - fat.count)
        let data = Data(fat) + other + arm
        #expect(EntitlementReader.entitlements(inExecutable: data).cloudKitContainers == ["iCloud.com.example.fat"])
    }

    @Test func garbageIsTreatedAsUnsigned() {
        #expect(EntitlementReader.entitlements(inExecutable: Data()) == .none)
        #expect(EntitlementReader.entitlements(inExecutable: Data(repeating: 7, count: 200)) == .none)
        var truncated = Self.machO(entitlementsXML: nil)
        truncated.removeLast(10)
        #expect(EntitlementReader.entitlements(inExecutable: truncated) == .none)
    }
}
