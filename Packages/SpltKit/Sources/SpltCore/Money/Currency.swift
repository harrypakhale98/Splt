/// Currency facts the engine needs, mainly how many decimal places a currency has.
public enum Currency {
    private static let zeroDecimalCodes: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG",
        "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF"
    ]

    private static let threeDecimalCodes: Set<String> = [
        "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"
    ]

    /// Number of decimal places in the major unit. 0 for JPY and friends, 3 for KWD and friends, otherwise 2.
    public static func minorUnitExponent(for code: String) -> Int {
        let code = code.uppercased()
        if zeroDecimalCodes.contains(code) { return 0 }
        if threeDecimalCodes.contains(code) { return 3 }
        return 2
    }

    /// How many minor units make one major unit, for example 100 for USD.
    public static func minorUnitScale(for code: String) -> Int64 {
        switch minorUnitExponent(for: code) {
        case 0: 1
        case 3: 1_000
        default: 100
        }
    }
}
