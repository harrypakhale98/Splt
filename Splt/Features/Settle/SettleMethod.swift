import Foundation
import SpltCore

/// How a payment was made outside the app, and where to open an app that can make it.
///
/// Only public web addresses and documented app schemes are used. Nothing here talks to a
/// payment service: it just opens the app or page on the device.
enum SettleMethod: String, CaseIterable, Identifiable, Sendable {
    case cash
    case bankTransfer
    case appleCash
    case venmo
    case paypal
    case cashApp
    case zelle
    case revolut
    case wise
    case upi
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: String(localized: "Cash")
        case .bankTransfer: String(localized: "Bank Transfer")
        case .appleCash: String(localized: "Apple Cash")
        case .venmo: String(localized: "Venmo")
        case .paypal: String(localized: "PayPal")
        case .cashApp: String(localized: "Cash App")
        case .zelle: String(localized: "Zelle")
        case .revolut: String(localized: "Revolut")
        case .wise: String(localized: "Wise")
        case .upi: String(localized: "UPI")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .cash: "banknote"
        case .bankTransfer: "building.columns"
        case .appleCash: "apple.logo"
        case .upi: "indianrupeesign.circle"
        case .other: "ellipsis.circle"
        case .venmo, .paypal, .cashApp, .zelle, .revolut, .wise: "dollarsign.circle"
        }
    }

    /// Whether a button can open an app or page for this method.
    var supportsPayWith: Bool {
        switch self {
        case .cash, .bankTransfer, .other: false
        default: true
        }
    }

    /// The address to open for a payment of `amount`, or nil when there is none for this method.
    /// `recipient` is whatever the receiver shared, such as a username or a UPI address; it is
    /// only passed on when it fits the method.
    func paymentURL(amount: Money, note: String, recipient: String?) -> URL? {
        let handle = recipient?.trimmingCharacters(in: .whitespacesAndNewlines)
        let figure = amount.plainString(locale: Locale(identifier: "en_US_POSIX"))
        switch self {
        case .cash, .bankTransfer, .other:
            return nil
        case .appleCash:
            let phone = handle.flatMap { Self.looksLikePhone($0) ? $0.filter { $0.isNumber || $0 == "+" } : nil }
            return URL(string: "sms:\(phone ?? "")")
        case .venmo:
            var items = [URLQueryItem(name: "txn", value: "pay")]
            if let handle, !handle.isEmpty { items.append(URLQueryItem(name: "recipients", value: handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))) }
            items.append(URLQueryItem(name: "amount", value: figure))
            if !note.isEmpty { items.append(URLQueryItem(name: "note", value: note)) }
            return Self.url("venmo://paycharge", items)
        case .paypal:
            if let handle, Self.looksLikeUsername(handle) {
                return URL(string: "https://paypal.me/\(Self.pathSafe(handle))/\(figure)\(amount.currencyCode)")
            }
            return URL(string: "https://www.paypal.com/myaccount/transfer/homepage/send")
        case .cashApp:
            if let handle, handle.hasPrefix("$"), Self.looksLikeUsername(String(handle.dropFirst())) {
                return URL(string: "https://cash.app/\(Self.pathSafe(handle))/\(figure)")
            }
            return URL(string: "https://cash.app")
        case .zelle:
            return URL(string: "https://www.zellepay.com")
        case .revolut:
            if let handle, Self.looksLikeUsername(handle) {
                return URL(string: "https://revolut.me/\(Self.pathSafe(handle))")
            }
            return URL(string: "https://revolut.me")
        case .wise:
            return URL(string: "https://wise.com/send")
        case .upi:
            guard amount.currencyCode == "INR" else { return nil }
            var items: [URLQueryItem] = []
            if let handle, Self.looksLikeUPIAddress(handle) { items.append(URLQueryItem(name: "pa", value: handle)) }
            items.append(URLQueryItem(name: "am", value: figure))
            items.append(URLQueryItem(name: "cu", value: "INR"))
            if !note.isEmpty { items.append(URLQueryItem(name: "tn", value: note)) }
            return Self.url("upi://pay", items)
        }
    }

    private static func url(_ base: String, _ items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items
        return components?.url
    }

    private static func pathSafe(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
    }

    private static func looksLikeUsername(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 40 && text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" }
    }

    private static func looksLikePhone(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        return digits.count >= 7 && !text.contains("@") && text.allSatisfy { $0.isNumber || "+ ()-.".contains($0) }
    }

    /// A UPI address is a name, an at sign and a handle with no dots, unlike an email address.
    private static func looksLikeUPIAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty && !parts[1].contains(".") && !text.contains(" ")
    }
}

/// The note stored on a payment: the method, then what the person typed.
enum SettleNote {
    static func compose(method: SettleMethod, text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard method != .other else { return trimmed }
        return trimmed.isEmpty ? method.title : "\(method.title): \(trimmed)"
    }
}
