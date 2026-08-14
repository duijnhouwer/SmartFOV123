import Foundation

struct RGB: Decodable, Sendable {
    let red: Float
    let green: Float
    let blue: Float

    init(from decoder: Decoder) throws {
        let values = try [Float](from: decoder)
        guard values.count == 3 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "RGB colors require exactly three values.")
            )
        }
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "RGB values must be finite and between 0.0 and 1.0.")
            )
        }
        red = values[0]
        green = values[1]
        blue = values[2]
    }
}

struct ExperimentConfiguration: Decodable, Sendable {
    let schemaVersion: Int
    let display: DisplayConfiguration
    let speech: SpeechConfiguration
    let stimulus: StimulusConfiguration
}

enum DisplayMode: String, Decodable, CaseIterable, Sendable {
    case videoPassthrough
    case opticalSeeThroughSimulation

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let mode = Self(rawValue: value) else {
            let allowedValues = Self.allCases.map(\.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid value ‘\(value)’; expected one of: \(allowedValues)."
            )
        }
        self = mode
    }
}

struct DisplayConfiguration: Decodable, Sendable {
    let mode: DisplayMode
    let peakOpacity: Float
}

struct SpeechConfiguration: Decodable, Sendable {
    let digitAliases: [String: [String]]

    var aliasLookup: [String: Int] {
        var lookup: [String: Int] = [:]
        for (digit, aliases) in digitAliases {
            guard let value = Int(digit) else { continue }
            for alias in aliases {
                lookup[Self.normalize(alias)] = value
            }
        }
        return lookup
    }

    static func normalize(_ alias: String) -> String {
        alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum StimulusEye: String, Decodable, Sendable {
    case left
    case right
    case both
}

struct StimulusConfiguration: Decodable, Sendable {
    let eye: StimulusEye
    let targetNumber: String
    let randomSeed: UInt64

    let digitHeightArcmin: Float
    let digitFontName: String
    let digitRGB: RGB

    let digitBoxWidthArcmin: Float
    let digitBoxHeightArcmin: Float
    let digitBoxStrokeArcmin: Float
    let digitBoxFillRGB: RGB
    let digitBoxStrokeRGB: RGB

    let numberOfDigitBoxesHorizontal: Int
    let numberOfDigitBoxesVertical: Int

    let digitGridHorizontalDeltaDegrees: Float
    let digitGridVerticalDeltaDegrees: Float

    let fovWidthDegrees: Float
    let fovHeightDegrees: Float
    let fovHorizontalOffsetDegrees: Float
    let fovVerticalOffsetDegrees: Float
    let fovBackgroundRGB: RGB
    let fovBorderStrokeArcmin: Float
    let fovBorderRGB: RGB

    let distanceMeters: Float
}

struct NumberGrid: Sendable {
    enum Orientation: String, Sendable {
        case horizontal
        case vertical
    }

    struct Placement: Equatable, Sendable {
        let row: Int
        let column: Int
        let orientation: Orientation
    }

    let rows: Int
    let columns: Int
    let digits: [UInt8]
    let targetNumber: String
    let targetPlacement: Placement
    let verificationCode: String

    func digit(at index: Int) -> Character {
        Character(UnicodeScalar(digits[index]))
    }
}

struct Experiment: Sendable {
    let configuration: ExperimentConfiguration
    let grid: NumberGrid

    static func loadBundled() throws -> Experiment {
        guard let url = Bundle.main.url(forResource: "experiment", withExtension: "json") else {
            throw ExperimentError.missingConfiguration
        }

        return try load(from: url)
    }

    static func load(from url: URL) throws -> Experiment {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ExperimentError.unreadableConfiguration(error)
        }

        let configuration: ExperimentConfiguration
        do {
            configuration = try JSONDecoder().decode(ExperimentConfiguration.self, from: data)
        } catch let error as DecodingError {
            throw ExperimentError.invalidConfiguration(describe(error))
        } catch {
            throw ExperimentError.invalidConfiguration(error.localizedDescription)
        }

        try configuration.validate()
        return Experiment(
            configuration: configuration,
            grid: try NumberGridGenerator.makeGrid(using: configuration.stimulus)
        )
    }

    private static func describe(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        let path: [CodingKey]
        switch error {
        case .typeMismatch(_, let errorContext),
             .valueNotFound(_, let errorContext),
             .dataCorrupted(let errorContext):
            context = errorContext
            path = errorContext.codingPath
        case .keyNotFound(let key, let errorContext):
            context = errorContext
            path = errorContext.codingPath + [key]
        @unknown default:
            return error.localizedDescription
        }

        let jsonPath = path.reduce("$") { result, key in
            if let index = key.intValue {
                return "\(result)[\(index)]"
            }
            return "\(result).\(key.stringValue)"
        }
        return "\(jsonPath): \(context.debugDescription)"
    }
}

enum ExperimentError: LocalizedError {
    case missingConfiguration
    case unreadableConfiguration(Error)
    case invalidConfiguration(String)
    case gridGenerationFailed

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "The bundled experiment.json file is missing."
        case .unreadableConfiguration(let error):
            return "experiment.json couldn't be read: \(error.localizedDescription)"
        case .invalidConfiguration(let message):
            return "experiment.json is invalid: \(message)"
        case .gridGenerationFailed:
            return "A valid NumberFinder grid couldn't be generated from the configured seed."
        }
    }
}

private extension ExperimentConfiguration {
    func validate() throws {
        guard schemaVersion == 3 else {
            throw ExperimentError.invalidConfiguration(
                "schemaVersion \(schemaVersion) is unsupported; this app requires version 3."
            )
        }

        guard display.peakOpacity.isFinite,
              (0...1).contains(display.peakOpacity) else {
            throw ExperimentError.invalidConfiguration(
                "display.peakOpacity must be a finite value between 0.0 and 1.0."
            )
        }

        let requiredDigitKeys = Set((0...9).map(String.init))
        guard Set(speech.digitAliases.keys) == requiredDigitKeys else {
            throw ExperimentError.invalidConfiguration(
                "speech.digitAliases must contain exactly the keys 0 through 9."
            )
        }
        var aliasOwners: [String: String] = [:]
        for digit in requiredDigitKeys {
            guard let aliases = speech.digitAliases[digit], !aliases.isEmpty else {
                throw ExperimentError.invalidConfiguration(
                    "speech.digitAliases.\(digit) must contain at least one spoken form."
                )
            }
            for alias in aliases {
                let normalized = SpeechConfiguration.normalize(alias)
                guard !normalized.isEmpty,
                      normalized.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else {
                    throw ExperimentError.invalidConfiguration(
                        "speech.digitAliases.\(digit) contains ‘\(alias)’; aliases must be single words containing letters only."
                    )
                }
                if let existingDigit = aliasOwners[normalized], existingDigit != digit {
                    throw ExperimentError.invalidConfiguration(
                        "The speech alias ‘\(normalized)’ is assigned to both \(existingDigit) and \(digit)."
                    )
                }
                aliasOwners[normalized] = digit
            }
        }

        let config = stimulus
        let number = config.targetNumber
        guard number.count == 3,
              number.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else {
            throw ExperimentError.invalidConfiguration("targetNumber must contain exactly three digits (0–9).")
        }
        guard config.numberOfDigitBoxesHorizontal >= 3,
              config.numberOfDigitBoxesVertical >= 3 else {
            throw ExperimentError.invalidConfiguration(
                "The digit grid must be at least 3 × 3 so every target can have a three-digit perpendicular crossing."
            )
        }
        guard config.numberOfDigitBoxesHorizontal <= 254,
              config.numberOfDigitBoxesVertical <= 254 else {
            throw ExperimentError.invalidConfiguration("Each digit-grid dimension may be at most 254.")
        }
        guard number.count <= config.numberOfDigitBoxesHorizontal
                || number.count <= config.numberOfDigitBoxesVertical else {
            throw ExperimentError.invalidConfiguration("targetNumber does not fit horizontally or vertically in the grid.")
        }

        let positiveValues: [(String, Float)] = [
            ("digitHeightArcmin", config.digitHeightArcmin),
            ("digitBoxWidthArcmin", config.digitBoxWidthArcmin),
            ("digitBoxHeightArcmin", config.digitBoxHeightArcmin),
            ("fovWidthDegrees", config.fovWidthDegrees),
            ("fovHeightDegrees", config.fovHeightDegrees),
            ("distanceMeters", config.distanceMeters)
        ]
        for (name, value) in positiveValues where !value.isFinite || value <= 0 {
            throw ExperimentError.invalidConfiguration("\(name) must be a finite value greater than zero.")
        }

        let nonnegativeValues: [(String, Float)] = [
            ("digitBoxStrokeArcmin", config.digitBoxStrokeArcmin),
            ("fovBorderStrokeArcmin", config.fovBorderStrokeArcmin)
        ]
        for (name, value) in nonnegativeValues where !value.isFinite || value < 0 {
            throw ExperimentError.invalidConfiguration("\(name) must be a finite value of zero or greater.")
        }
        let offsetValues: [(String, Float)] = [
            ("digitGridHorizontalDeltaDegrees", config.digitGridHorizontalDeltaDegrees),
            ("digitGridVerticalDeltaDegrees", config.digitGridVerticalDeltaDegrees),
            ("fovHorizontalOffsetDegrees", config.fovHorizontalOffsetDegrees),
            ("fovVerticalOffsetDegrees", config.fovVerticalOffsetDegrees)
        ]
        for (name, value) in offsetValues where !value.isFinite {
            throw ExperimentError.invalidConfiguration("\(name) must be finite.")
        }
        guard config.digitBoxStrokeArcmin * 2 < min(
            config.digitBoxWidthArcmin,
            config.digitBoxHeightArcmin
        ) else {
            throw ExperimentError.invalidConfiguration("digitBoxStrokeArcmin is too large for the configured boxes.")
        }
        guard config.fovBorderStrokeArcmin * 2 < min(
            config.fovWidthDegrees * 60,
            config.fovHeightDegrees * 60
        ) else {
            throw ExperimentError.invalidConfiguration("fovBorderStrokeArcmin is too large for the configured FOV.")
        }
        guard !config.digitFontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExperimentError.invalidConfiguration("digitFontName must not be empty.")
        }
    }
}

private enum NumberGridGenerator {
    static func makeGrid(using config: StimulusConfiguration) throws -> NumberGrid {
        let rows = config.numberOfDigitBoxesVertical
        let columns = config.numberOfDigitBoxesHorizontal
        let number = Array(config.targetNumber.utf8)
        let orientations = NumberGrid.Orientation.allThatFit(
            numberLength: number.count,
            rows: rows,
            columns: columns
        )
        var random = SplitMix64(seed: config.randomSeed)

        for _ in 0..<10_000 {
            var digits = (0..<(rows * columns)).map { _ in
                UInt8(48 + random.nextInt(upperBound: 10))
            }
            let orientation = orientations[random.nextInt(upperBound: orientations.count)]
            let placement: NumberGrid.Placement

            switch orientation {
            case .horizontal:
                placement = .init(
                    row: 1 + random.nextInt(upperBound: rows - 2),
                    column: random.nextInt(upperBound: columns - number.count + 1),
                    orientation: orientation
                )
            case .vertical:
                placement = .init(
                    row: random.nextInt(upperBound: rows - number.count + 1),
                    column: 1 + random.nextInt(upperBound: columns - 2),
                    orientation: orientation
                )
            }

            for (offset, digit) in number.enumerated() {
                let row = placement.row + (orientation == .vertical ? offset : 0)
                let column = placement.column + (orientation == .horizontal ? offset : 0)
                digits[row * columns + column] = digit
            }

            let occurrences = findOccurrences(
                of: number,
                in: digits,
                rows: rows,
                columns: columns
            )
            guard occurrences == [placement] else { continue }

            let middleOffset = number.count / 2
            let middleRow = placement.row + (orientation == .vertical ? middleOffset : 0)
            let middleColumn = placement.column + (orientation == .horizontal ? middleOffset : 0)
            let verificationIndices: [Int]
            let verificationPlacement: NumberGrid.Placement
            switch orientation {
            case .horizontal:
                verificationIndices = [middleRow - 1, middleRow, middleRow + 1].map {
                    $0 * columns + middleColumn
                }
                verificationPlacement = .init(
                    row: middleRow - 1,
                    column: middleColumn,
                    orientation: .vertical
                )
            case .vertical:
                verificationIndices = [middleColumn - 1, middleColumn, middleColumn + 1].map {
                    middleRow * columns + $0
                }
                verificationPlacement = .init(
                    row: middleRow,
                    column: middleColumn - 1,
                    orientation: .horizontal
                )
            }
            let verificationDigits = verificationIndices.map { digits[$0] }
            let verificationOccurrences = findOccurrences(
                of: verificationDigits,
                in: digits,
                rows: rows,
                columns: columns
            )
            guard verificationOccurrences == [verificationPlacement] else { continue }

            let verificationCode = String(
                bytes: verificationDigits,
                encoding: .ascii
            )!

            return NumberGrid(
                rows: rows,
                columns: columns,
                digits: digits,
                targetNumber: config.targetNumber,
                targetPlacement: placement,
                verificationCode: verificationCode
            )
        }

        throw ExperimentError.gridGenerationFailed
    }

    private static func findOccurrences(
        of number: [UInt8],
        in digits: [UInt8],
        rows: Int,
        columns: Int
    ) -> [NumberGrid.Placement] {
        var matches: [NumberGrid.Placement] = []

        if number.count <= columns {
            for row in 0..<rows {
                for column in 0...(columns - number.count) {
                    let isMatch = number.indices.allSatisfy { offset in
                        digits[row * columns + column + offset] == number[offset]
                    }
                    if isMatch {
                        matches.append(.init(row: row, column: column, orientation: .horizontal))
                    }
                }
            }
        }

        if number.count <= rows {
            for row in 0...(rows - number.count) {
                for column in 0..<columns {
                    let isMatch = number.indices.allSatisfy { offset in
                        digits[(row + offset) * columns + column] == number[offset]
                    }
                    if isMatch {
                        matches.append(.init(row: row, column: column, orientation: .vertical))
                    }
                }
            }
        }

        return matches
    }
}

private extension NumberGrid.Orientation {
    static func allThatFit(numberLength: Int, rows: Int, columns: Int) -> [Self] {
        var orientations: [Self] = []
        if numberLength <= columns, rows >= 3 { orientations.append(.horizontal) }
        if numberLength <= rows, columns >= 3 { orientations.append(.vertical) }
        return orientations
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }
}
