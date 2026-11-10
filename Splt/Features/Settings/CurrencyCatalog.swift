import Foundation

struct CurrencyOption: Identifiable, Hashable, Sendable {
    let code: String
    let name: String

    var id: String { code }
}

enum CurrencyCatalog {
    static func options(locale: Locale = .current) -> [CurrencyOption] {
        Locale.commonISOCurrencyCodes
            .map { CurrencyOption(code: $0, name: name(for: $0, locale: locale)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The same list as `options(locale:)`, built once per locale. Pickers ask on every keystroke.
    @MainActor
    static func cachedOptions(locale: Locale = .current) -> [CurrencyOption] {
        if let cached = cache[locale.identifier] { return cached }
        let built = options(locale: locale)
        cache[locale.identifier] = built
        return built
    }

    @MainActor private static var cache: [String: [CurrencyOption]] = [:]

    static func name(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }

    /// Matches the code or the localized name, ignoring case and accents.
    static func filter(_ options: [CurrencyOption], query: String) -> [CurrencyOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return options }
        return options.filter {
            $0.code.localizedStandardContains(trimmed) || $0.name.localizedStandardContains(trimmed)
        }
    }
}
