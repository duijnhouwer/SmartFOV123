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
    let stimulus: StimulusConfiguration
}

enum StimulusEye: String, Decodable, Sendable {
    case left
    case right
    case both
}

struct StimulusConfiguration: Decodable, Sendable {
    let eye: StimulusEye
    let targetWord: String
    let randomSeed: UInt64

    let letterHeightArcmin: Float
    let letterFontName: String
    let letterRGB: RGB

    let letterBoxWidthArcmin: Float
    let letterBoxHeightArcmin: Float
    let letterBoxStrokeArcmin: Float
    let letterBoxFillRGB: RGB
    let letterBoxStrokeRGB: RGB

    let numberOfLetterBoxesHorizontal: Int
    let numberOfLetterBoxesVertical: Int

    let letterGridHorizontalDeltaDegrees: Float
    let letterGridVerticalDeltaDegrees: Float

    let fovWidthDegrees: Float
    let fovHeightDegrees: Float
    let fovHorizontalOffsetDegrees: Float
    let fovVerticalOffsetDegrees: Float
    let fovBackgroundRGB: RGB
    let fovBorderStrokeArcmin: Float
    let fovBorderRGB: RGB

    let distanceMeters: Float
}

struct WordGrid: Sendable {
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
    let letters: [UInt8]
    let targetWord: String
    let targetPlacement: Placement
    let targetMiddleIndex: Int

    func letter(at index: Int) -> Character {
        Character(UnicodeScalar(letters[index]))
    }
}

struct Experiment: Sendable {
    let configuration: ExperimentConfiguration
    let grid: WordGrid

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
        } catch {
            throw ExperimentError.invalidConfiguration(error.localizedDescription)
        }

        try configuration.validate()
        return Experiment(
            configuration: configuration,
            grid: try WordGridGenerator.makeGrid(using: configuration.stimulus)
        )
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
            return "A valid WordFinder grid couldn't be generated from the configured seed."
        }
    }
}

private extension ExperimentConfiguration {
    func validate() throws {
        guard schemaVersion == 1 else {
            throw ExperimentError.invalidConfiguration(
                "schemaVersion \(schemaVersion) is unsupported; this app requires version 1."
            )
        }

        let config = stimulus
        let word = config.targetWord
        guard word == word.uppercased(),
              word.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else {
            throw ExperimentError.invalidConfiguration("targetWord must contain uppercase A–Z only.")
        }
        guard word.count >= 3, word.count.isMultiple(of: 2) == false else {
            throw ExperimentError.invalidConfiguration(
                "targetWord must contain an odd number of at least three letters so it has one selectable middle letter."
            )
        }
        guard config.numberOfLetterBoxesHorizontal > 0,
              config.numberOfLetterBoxesVertical > 0 else {
            throw ExperimentError.invalidConfiguration("The letter-grid dimensions must be positive.")
        }
        guard config.numberOfLetterBoxesHorizontal <= 254,
              config.numberOfLetterBoxesVertical <= 254 else {
            throw ExperimentError.invalidConfiguration("Each letter-grid dimension may be at most 254.")
        }
        let cellCount = config.numberOfLetterBoxesHorizontal * config.numberOfLetterBoxesVertical
        guard cellCount <= 254 else {
            throw ExperimentError.invalidConfiguration(
                "The grid may contain at most 254 boxes when using 8-bit visionOS tracking areas."
            )
        }
        guard word.count <= config.numberOfLetterBoxesHorizontal
                || word.count <= config.numberOfLetterBoxesVertical else {
            throw ExperimentError.invalidConfiguration("targetWord does not fit horizontally or vertically in the grid.")
        }

        let positiveValues: [(String, Float)] = [
            ("letterHeightArcmin", config.letterHeightArcmin),
            ("letterBoxWidthArcmin", config.letterBoxWidthArcmin),
            ("letterBoxHeightArcmin", config.letterBoxHeightArcmin),
            ("fovWidthDegrees", config.fovWidthDegrees),
            ("fovHeightDegrees", config.fovHeightDegrees),
            ("distanceMeters", config.distanceMeters)
        ]
        for (name, value) in positiveValues where !value.isFinite || value <= 0 {
            throw ExperimentError.invalidConfiguration("\(name) must be a finite value greater than zero.")
        }

        let nonnegativeValues: [(String, Float)] = [
            ("letterBoxStrokeArcmin", config.letterBoxStrokeArcmin),
            ("fovBorderStrokeArcmin", config.fovBorderStrokeArcmin)
        ]
        for (name, value) in nonnegativeValues where !value.isFinite || value < 0 {
            throw ExperimentError.invalidConfiguration("\(name) must be a finite value of zero or greater.")
        }
        let offsetValues: [(String, Float)] = [
            ("letterGridHorizontalDeltaDegrees", config.letterGridHorizontalDeltaDegrees),
            ("letterGridVerticalDeltaDegrees", config.letterGridVerticalDeltaDegrees),
            ("fovHorizontalOffsetDegrees", config.fovHorizontalOffsetDegrees),
            ("fovVerticalOffsetDegrees", config.fovVerticalOffsetDegrees)
        ]
        for (name, value) in offsetValues where !value.isFinite {
            throw ExperimentError.invalidConfiguration("\(name) must be finite.")
        }
        guard config.letterBoxStrokeArcmin * 2 < min(
            config.letterBoxWidthArcmin,
            config.letterBoxHeightArcmin
        ) else {
            throw ExperimentError.invalidConfiguration("letterBoxStrokeArcmin is too large for the configured boxes.")
        }
        guard config.fovBorderStrokeArcmin * 2 < min(
            config.fovWidthDegrees * 60,
            config.fovHeightDegrees * 60
        ) else {
            throw ExperimentError.invalidConfiguration("fovBorderStrokeArcmin is too large for the configured FOV.")
        }
        guard !config.letterFontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExperimentError.invalidConfiguration("letterFontName must not be empty.")
        }
    }
}

private enum WordGridGenerator {
    static func makeGrid(using config: StimulusConfiguration) throws -> WordGrid {
        let rows = config.numberOfLetterBoxesVertical
        let columns = config.numberOfLetterBoxesHorizontal
        let word = Array(config.targetWord.utf8)
        let orientations = WordGrid.Orientation.allThatFit(
            wordLength: word.count,
            rows: rows,
            columns: columns
        )
        var random = SplitMix64(seed: config.randomSeed)

        for _ in 0..<10_000 {
            var letters = (0..<(rows * columns)).map { _ in
                UInt8(65 + random.nextInt(upperBound: 26))
            }
            let orientation = orientations[random.nextInt(upperBound: orientations.count)]
            let placement: WordGrid.Placement

            switch orientation {
            case .horizontal:
                placement = .init(
                    row: random.nextInt(upperBound: rows),
                    column: random.nextInt(upperBound: columns - word.count + 1),
                    orientation: orientation
                )
            case .vertical:
                placement = .init(
                    row: random.nextInt(upperBound: rows - word.count + 1),
                    column: random.nextInt(upperBound: columns),
                    orientation: orientation
                )
            }

            for (offset, character) in word.enumerated() {
                let row = placement.row + (orientation == .vertical ? offset : 0)
                let column = placement.column + (orientation == .horizontal ? offset : 0)
                letters[row * columns + column] = character
            }

            let occurrences = findOccurrences(
                of: word,
                in: letters,
                rows: rows,
                columns: columns
            )
            guard occurrences == [placement] else { continue }

            let middleOffset = word.count / 2
            let middleRow = placement.row + (orientation == .vertical ? middleOffset : 0)
            let middleColumn = placement.column + (orientation == .horizontal ? middleOffset : 0)
            return WordGrid(
                rows: rows,
                columns: columns,
                letters: letters,
                targetWord: config.targetWord,
                targetPlacement: placement,
                targetMiddleIndex: middleRow * columns + middleColumn
            )
        }

        throw ExperimentError.gridGenerationFailed
    }

    private static func findOccurrences(
        of word: [UInt8],
        in letters: [UInt8],
        rows: Int,
        columns: Int
    ) -> [WordGrid.Placement] {
        var matches: [WordGrid.Placement] = []

        if word.count <= columns {
            for row in 0..<rows {
                for column in 0...(columns - word.count) {
                    let isMatch = word.indices.allSatisfy { offset in
                        letters[row * columns + column + offset] == word[offset]
                    }
                    if isMatch {
                        matches.append(.init(row: row, column: column, orientation: .horizontal))
                    }
                }
            }
        }

        if word.count <= rows {
            for row in 0...(rows - word.count) {
                for column in 0..<columns {
                    let isMatch = word.indices.allSatisfy { offset in
                        letters[(row + offset) * columns + column] == word[offset]
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

private extension WordGrid.Orientation {
    static func allThatFit(wordLength: Int, rows: Int, columns: Int) -> [Self] {
        var orientations: [Self] = []
        if wordLength <= columns { orientations.append(.horizontal) }
        if wordLength <= rows { orientations.append(.vertical) }
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
