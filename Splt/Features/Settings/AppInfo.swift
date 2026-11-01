import Foundation

enum AppInfo {
    static let sourceCodeURL = URL(string: "https://github.com/harrypakhale98/Splt")!

    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
