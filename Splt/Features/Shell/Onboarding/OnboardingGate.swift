import Foundation

/// Decides whether the welcome tour opens at launch.
enum OnboardingGate {
    /// In debug builds, UI tests and sample data runs skip it and `-onboarding` forces it, for screenshots and tests.
    static func shouldShow(arguments: [String], completed: Bool) -> Bool {
        #if DEBUG
        if arguments.contains("-onboarding") { return true }
        if arguments.contains("-uitesting") || arguments.contains("-sampledata") { return false }
        #endif
        return !completed
    }

    /// Read as the app starts, before any file or link it was opened with is handled.
    static func shouldShowAtLaunch(
        arguments: [String] = ProcessInfo.processInfo.arguments, defaults: UserDefaults = .standard
    ) -> Bool {
        shouldShow(arguments: arguments, completed: defaults.bool(forKey: Preferences.Key.onboardingCompleted))
    }
}
