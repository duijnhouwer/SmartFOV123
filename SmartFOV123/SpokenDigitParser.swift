import Foundation

enum SpokenDigitParser {
    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]

    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    static func parseDigits(
        from transcript: String,
        aliases: [String: Int],
        digitCount: Int
    ) -> String? {
        guard digitCount > 0 else { return nil }
        if digitCount == 3 {
            return parseThreeDigits(from: transcript, aliases: aliases)
        }

        let tokens = transcript
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        guard let flattened = flattenDigitTokens(tokens, aliases: aliases),
              flattened.count == digitCount else {
            return nil
        }
        return flattened
    }

    static func parseThreeDigits(
        from transcript: String,
        aliases: [String: Int]
    ) -> String? {
        let tokens = transcript
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)

        guard !tokens.isEmpty else { return nil }

        if let flattened = flattenDigitTokens(tokens, aliases: aliases), flattened.count == 3 {
            return flattened
        }

        if let value = parseCardinal(tokens, aliases: aliases), (100...999).contains(value) {
            return String(format: "%03d", value)
        }

        if tokens.count >= 2,
           let first = aliases[tokens[0]],
           let remaining = parseCardinal(Array(tokens.dropFirst()), aliases: aliases),
           (10...99).contains(remaining) {
            return "\(first)" + String(format: "%02d", remaining)
        }

        return nil
    }

    static func normalizedForStorage(
        _ transcript: String,
        aliases: [String: Int]
    ) -> String {
        let tokens = transcript
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)

        guard !tokens.isEmpty else { return transcript }

        let mappedTokens = tokens.map { token in
            aliases[token.lowercased()].map(String.init) ?? token
        }

        if mappedTokens.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            return mappedTokens.joined()
        }
        return mappedTokens.joined(separator: " ")
    }

    private static func flattenDigitTokens(
        _ tokens: [String],
        aliases: [String: Int]
    ) -> String? {
        var result = ""
        for token in tokens {
            if token.allSatisfy(\.isNumber) {
                result += token
            } else if let digit = aliases[token] {
                result += String(digit)
            } else {
                return nil
            }
        }
        return result
    }

    private static func parseCardinal(
        _ tokens: [String],
        aliases: [String: Int]
    ) -> Int? {
        guard !tokens.isEmpty else { return nil }

        var value = 0
        var sawNumber = false
        for token in tokens where token != "and" {
            if let digit = aliases[token] {
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
