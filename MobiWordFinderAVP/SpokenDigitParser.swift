import Foundation

enum SpokenDigitParser {
    private static let singleDigits: [String: Int] = [
        "zero": 0, "oh": 0, "o": 0,
        "one": 1, "won": 1,
        "two": 2, "to": 2, "too": 2,
        "three": 3,
        "four": 4, "for": 4, "fore": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
        "eight": 8, "ate": 8,
        "nine": 9
    ]

    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]

    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    static func parseThreeDigits(from transcript: String) -> String? {
        let tokens = transcript
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)

        guard !tokens.isEmpty else { return nil }

        if let flattened = flattenDigitTokens(tokens), flattened.count == 3 {
            return flattened
        }

        if let value = parseCardinal(tokens), (100...999).contains(value) {
            return String(format: "%03d", value)
        }

        if tokens.count >= 2,
           let first = singleDigits[tokens[0]],
           let remaining = parseCardinal(Array(tokens.dropFirst())),
           (10...99).contains(remaining) {
            return "\(first)" + String(format: "%02d", remaining)
        }

        return nil
    }

    private static func flattenDigitTokens(_ tokens: [String]) -> String? {
        var result = ""
        for token in tokens {
            if token.allSatisfy(\.isNumber) {
                result += token
            } else if let digit = singleDigits[token] {
                result += String(digit)
            } else {
                return nil
            }
        }
        return result
    }

    private static func parseCardinal(_ tokens: [String]) -> Int? {
        guard !tokens.isEmpty else { return nil }

        var value = 0
        var sawNumber = false
        for token in tokens where token != "and" {
            if let digit = singleDigits[token] {
                value += digit
                sawNumber = true
            } else if let teen = teens[token] {
                value += teen
                sawNumber = true
            } else if let multiple = tens[token] {
                value += multiple
                sawNumber = true
            } else if token == "hundred", (1...9).contains(value) {
                value *= 100
            } else {
                return nil
            }
        }
        return sawNumber ? value : nil
    }
}
