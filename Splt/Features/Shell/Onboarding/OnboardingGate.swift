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
}
