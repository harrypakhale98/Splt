import Foundation

/// Decides whether the welcome tour opens at launch.
enum OnboardingGate {
    /// UI tests and sample data runs skip it. `-onboarding` forces it, for screenshots and tests.
    static func shouldShow(arguments: [String], completed: Bool) -> Bool {
        if arguments.contains("-onboarding") { return true }
        if arguments.contains("-uitesting") || arguments.contains("-sampledata") { return false }
        return !completed
    }
}
