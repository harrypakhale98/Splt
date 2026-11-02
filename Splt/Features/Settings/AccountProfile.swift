import Foundation
import Observation
import UIKit

/// Who you are in Splt: the name others see and the payment details you add to reminders.
/// Everything is kept on this device, in `UserDefaults`.
@MainActor
@Observable
final class AccountProfile {
    static let shared = AccountProfile()

    static let nameKey = "profile.displayName"
    private static let handlePrefix = "profile.handle."

    /// What people can use to pay you. Only these methods have a handle worth sharing.
    static let handleMethods: [SettleMethod] = [.venmo, .cashApp, .paypal, .zelle, .revolut, .upi]

    var displayName: String
    private(set) var handles: [SettleMethod: String]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, deviceName: String = UIDevice.current.name) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.nameKey)
        displayName = saved ?? Self.suggestedName(fromDeviceName: deviceName) ?? ""
        var stored: [SettleMethod: String] = [:]
        for method in Self.handleMethods {
            if let value = defaults.string(forKey: Self.handlePrefix + method.rawValue), !value.isEmpty {
                stored[method] = value
            }
        }
        handles = stored
    }

    /// "Sam's iPhone" becomes "Sam". A plain "iPhone", which is what the system reports without
    /// permission to share the name, gives nothing.
    nonisolated static func suggestedName(fromDeviceName deviceName: String) -> String? {
        for marker in ["'s ", "\u{2019}s "] {
            guard let range = deviceName.range(of: marker) else { continue }
            let owner = deviceName[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let device = deviceName[range.upperBound...].lowercased()
            let looksLikeDevice = ["iphone", "ipad", "ipod"].contains { device.hasPrefix($0) }
            if looksLikeDevice, !owner.isEmpty, !owner.contains(where: \.isNumber) { return owner }
        }
        return nil
    }

    /// The name shown and shared. Falls back to "You" until one is set.
    var effectiveName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "You") : trimmed
    }

    var hasName: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func handle(for method: SettleMethod) -> String {
        handles[method] ?? ""
    }

    func setHandle(_ text: String, for method: SettleMethod) {
        let tidy = text.trimmingCharacters(in: .whitespacesAndNewlines)
        handles[method] = tidy.isEmpty ? nil : tidy
    }

    /// Writes the name and handles to the device.
    func save() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = trimmed
        defaults.set(trimmed, forKey: Self.nameKey)
        defaults.set(trimmed, forKey: AddFriendModel.inviteNameKey)
        for method in Self.handleMethods {
            let key = Self.handlePrefix + method.rawValue
            if let value = handles[method] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Makes the person that stands for you carry this name, so it is what friends and groups show.
    /// Does nothing until a name is set.
    func applyName(to people: any PersonRepository) throws {
        guard hasName else { return }
        var me = try people.ensureMe(name: effectiveName)
        guard me.name != effectiveName else { return }
        me.name = effectiveName
        try people.update(me)
    }

    // MARK: Messages

    /// "You can pay me with Venmo @sam and Cash App $sam." Nil when no handle is set.
    var paymentLine: String? {
        let parts = Self.handleMethods.compactMap { method -> String? in
            guard let value = handles[method] else { return nil }
            return "\(method.title) \(Self.displayForm(of: value, method: method))"
        }
        guard !parts.isEmpty else { return nil }
        let list = ListFormatter.localizedString(byJoining: parts)
        return String(localized: "You can pay me with \(list).")
    }

    /// The handle the way people write it: `@sam` for Venmo, `$sam` for Cash App.
    nonisolated static func displayForm(of handle: String, method: SettleMethod) -> String {
        let bare = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@$ "))
        switch method {
        case .venmo: return "@" + bare
        case .cashApp: return "$" + bare
        case .paypal: return "paypal.me/" + bare
        case .revolut: return "revolut.me/" + bare
        default: return handle
        }
    }
}

extension SettleMethod {
    /// The label for the field where you enter your own handle.
    var handleTitle: String {
        self == .upi ? String(localized: "UPI ID") : title
    }

    var handlePrompt: String {
        switch self {
        case .venmo: String(localized: "@username")
        case .cashApp: String(localized: "$cashtag")
        case .paypal, .revolut: String(localized: "username")
        case .zelle: String(localized: "Email or phone")
        case .upi: String(localized: "name@bank")
        default: ""
        }
    }
}
