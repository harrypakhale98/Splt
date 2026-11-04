import Foundation

/// Turns spelled out numbers from dictation ("sixty", "twenty five") into digits.
///
/// Small numbers such as "one" or "three" are left alone unless a currency word follows,
/// because "one night" or "three friends" are not prices.
enum NumberWords {
    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90
    ]
    private static let currencyWords: Set<String> = [
        "dollar", "dollars", "buck", "bucks", "euro", "euros", "pound", "pounds", "quid", "rupee", "rupees",
        "cent", "cents", "pence", "paise"
    ]

    static func replacingSpelledNumbers(in text: String) -> String {
        let spaced = text.replacingOccurrences(
            of: #"(?i)\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)-(one|two|three|four|five|six|seven|eight|nine)\b"#,
            with: "$1 $2",
            options: .regularExpression
        )
        let pieces = spaced.components(separatedBy: " ")
        var output: [String] = []
        var index = 0
        while index < pieces.count {
            if let run = parseRun(in: pieces, from: index) {
                let next = index + run.length < pieces.count ? pieces[index + run.length] : ""
                let followedByCurrency = currencyWords.contains(clean(next))
                if run.isLarge || followedByCurrency {
                    output.append(String(run.value) + run.trailingPunctuation)
                    index += run.length
                    continue
                }
            }
            output.append(pieces[index])
            index += 1
        }
        return output.joined(separator: " ")
    }

    private struct Run {
        var value: Int
        var length: Int
        var isLarge: Bool
        var trailingPunctuation: String
    }

    private static func clean(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    private static func trailing(_ word: String) -> String {
        String(word.reversed().prefix { $0.isPunctuation }.reversed())
    }

    /// Reads "a hundred and twenty five", "sixty", "two hundred" or "twenty five" starting at `start`.
    private static func parseRun(in pieces: [String], from start: Int) -> Run? {
        var total = 0
        var current = 0
        var consumed = 0
        var sawLarge = false
        var index = start
        var lastWordIndex = start

        while index < pieces.count {
            let word = clean(pieces[index])
            if let value = units[word] {
                if current % 10 != 0 || (current % 100 != 0 && current % 100 < 20 && current % 100 > 0) { break }
                current += value
            } else if let value = tens[word] {
                if current % 100 != 0 { break }
                current += value
                sawLarge = true
            } else if word == "hundred" {
                if current == 0 && index == start { break }
                current = max(current, 1) * 100
                sawLarge = true
            } else if word == "thousand" {
                total += max(current, 1) * 1000
                current = 0
                sawLarge = true
            } else if word == "a", index == start, index + 1 < pieces.count,
                      ["hundred", "thousand"].contains(clean(pieces[index + 1])) {
                index += 1
                continue
            } else if word == "and", consumed > 0, index + 1 < pieces.count,
                      (current >= 100 && current % 100 == 0) || (total > 0 && current == 0),
                      units[clean(pieces[index + 1])] != nil || tens[clean(pieces[index + 1])] != nil {
                index += 1
                continue
            } else {
                break
            }
            consumed += 1
            lastWordIndex = index
            index += 1
            if trailing(pieces[lastWordIndex]) != "" { break }
        }
        guard consumed > 0 else { return nil }
        let value = total + current
        return Run(
            value: value,
            length: lastWordIndex - start + 1,
            isLarge: sawLarge,
            trailingPunctuation: trailing(pieces[lastWordIndex])
        )
    }
}
