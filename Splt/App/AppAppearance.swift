import SwiftUI
import UIKit

/// Light or dark, or whatever the phone uses. Chosen in Account and applied to every window.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// The style for the windows: a launch argument pinned for screenshots wins over the setting.
    static func style(chosen: AppAppearance, launch: ColorScheme?) -> UIUserInterfaceStyle {
        switch launch {
        case .dark: .dark
        case .light: .light
        default: chosen.interfaceStyle
        }
    }
}

extension View {
    /// Applies the chosen appearance to every window of the app, sheets and alerts included. Setting
    /// the windows' style, rather than a preferred color scheme, lets System hand control back to the phone.
    func appAppearance() -> some View {
        modifier(AppAppearanceModifier())
    }
}

private struct AppAppearanceModifier: ViewModifier {
    @AppStorage(Preferences.Key.appearance) private var appearance: AppAppearance = .system
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear(perform: apply)
            .onChange(of: appearance) { apply() }
            .onChange(of: scenePhase) { apply() }
    }

    private func apply() {
        let style = AppAppearance.style(chosen: appearance, launch: LaunchAppearance.scheme())
        for scene in UIApplication.shared.connectedScenes {
            guard let windows = (scene as? UIWindowScene)?.windows else { continue }
            for window in windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
