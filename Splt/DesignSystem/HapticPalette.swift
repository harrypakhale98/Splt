import SwiftUI
import UIKit

/// The haptic vocabulary of the app. All of it is silent when Haptics is off in Settings.
enum HapticKind: Sendable {
    /// A light selection, such as choosing a chip.
    case tick
    /// A notch while dragging, such as reaching an equal split.
    case detent
    case success
    /// Settling a debt: a soft thump, a tick and a soft thump.
    case settle
    case warning

    var feedback: SensoryFeedback {
        switch self {
        case .tick: .selection
        case .detent: .alignment
        case .success: .success
        case .settle: .impact(flexibility: .soft, intensity: 0.8)
        case .warning: .warning
        }
    }
}

enum Haptics {
    /// Plays a haptic now, for moments that are not driven by a changing value.
    @MainActor
    static func play(_ kind: HapticKind, defaults: UserDefaults = .standard, reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled) {
        guard isEnabled(defaults) else { return }
        switch kind {
        case .tick:
            UISelectionFeedbackGenerator().selectionChanged()
        case .detent:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .settle:
            let soft = UIImpactFeedbackGenerator(style: .soft)
            guard !reduceMotion else {
                soft.impactOccurred()
                return
            }
            Task { @MainActor in
                soft.impactOccurred()
                try? await Task.sleep(for: .milliseconds(120))
                UISelectionFeedbackGenerator().selectionChanged()
                try? await Task.sleep(for: .milliseconds(120))
                soft.impactOccurred(intensity: 0.7)
            }
        }
    }

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Preferences.Key.hapticsEnabled) as? Bool ?? true
    }
}

extension View {
    /// Plays a palette haptic when `trigger` changes, unless Haptics is off in Settings.
    func haptics<T: Equatable>(_ kind: HapticKind, trigger: T) -> some View {
        haptic(kind.feedback, trigger: trigger)
    }
}
