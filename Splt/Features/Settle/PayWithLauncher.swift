import UIKit

/// What the "Pay with" button needs from the system, so tests do not open real apps.
@MainActor
protocol URLOpening {
    func canOpen(_ url: URL) -> Bool
    func open(_ url: URL) async -> Bool
}

struct SystemURLOpener: URLOpening {
    func canOpen(_ url: URL) -> Bool {
        UIApplication.shared.canOpenURL(url)
    }

    func open(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url)
    }
}

/// Opens a payment app and says when that was not possible, for example because it is not installed.
/// Custom schemes such as `venmo` and `upi` must be listed in `LSApplicationQueriesSchemes`,
/// otherwise `canOpenURL` answers no for them.
@MainActor
struct PayWithLauncher {
    enum Outcome: Equatable {
        case opened
        case unavailable
    }

    var opener: any URLOpening = SystemURLOpener()

    func launch(_ url: URL) async -> Outcome {
        guard opener.canOpen(url) else { return .unavailable }
        return await opener.open(url) ? .opened : .unavailable
    }
}

extension SettleMethod {
    /// The public site to look at when the app is not installed. Nil when there is no single one.
    var websiteURL: URL? {
        switch self {
        case .venmo: URL(string: "https://venmo.com")
        case .paypal: URL(string: "https://www.paypal.com")
        case .cashApp: URL(string: "https://cash.app")
        case .zelle: URL(string: "https://www.zellepay.com")
        case .revolut: URL(string: "https://www.revolut.com")
        case .wise: URL(string: "https://wise.com")
        case .appleCash: URL(string: "https://support.apple.com/apple-cash")
        case .cash, .bankTransfer, .upi, .other: nil
        }
    }
}
