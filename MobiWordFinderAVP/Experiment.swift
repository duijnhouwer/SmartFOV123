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

enum DisplayMode: String, Decodable, CaseIterable, Sendable {
    case videoPassthrough = "video_passthrough"
    case opticalSeeThroughSimulation = "optical_see_through_simulation"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let mode = Self(rawValue: value) else {
            let allowed = Self.allCases.map(\.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid value ‘\(value)’; expected one of: \(allowed)."
            )
        }
        self = mode
    }
}

enum StimulusEye: String, Decodable, Sendable {
    case left
    case right
    case both
}

struct DisplayConfiguration: Sendable {
    let mode: DisplayMode
    let peakOpacity: Float
}

struct SpeechConfiguration: Sendable {
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

struct StimulusConfiguration: Sendable {
    let eye: StimulusEye
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

    let fovWidthDegrees: Float
    let fovHeightDegrees: Float
    let fovHorizontalOffsetDegrees: Float
    let fovVerticalOffsetDegrees: Float
    let fovBackgroundRGB: RGB
    let fovBorderStrokeArcmin: Float
    let fovBorderRGB: RGB
    let distanceMeters: Float
}

struct ExperimentConfiguration: Sendable {
    let display: DisplayConfiguration
    let speech: SpeechConfiguration
    let stimulus: StimulusConfiguration
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
    let trialNumber: Int
    let conditionName: String
    let blockNumber: Int
    let configuration: ExperimentConfiguration
    let grid: NumberGrid
}

struct ScheduledTrial: Sendable {
    let trialNumber: Int
    let conditionName: String
    let blockNumber: Int
    let configuration: ExperimentConfiguration

    func instantiate() -> Experiment {
        Experiment(
            trialNumber: trialNumber,
            conditionName: conditionName,
            blockNumber: blockNumber,
            configuration: configuration,
            grid: NumberGridGenerator.makeGrid(using: configuration.stimulus)
        )
    }
}

struct ExperimentPlan: Sendable {
    let trials: [ScheduledTrial]

    static func loadBundled() throws -> ExperimentPlan {
        guard let url = Bundle.main.url(forResource: "experiment", withExtension: "json") else {
            throw ExperimentError.missingConfiguration
        }
        return try load(from: url)
    }

    static func load(from url: URL) throws -> ExperimentPlan {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ExperimentError.unreadableConfiguration(error)
        }

        do {
            try JSONShapeValidator.validate(data)
        } catch let error as ExperimentError {
            throw error
        } catch {
            throw ExperimentError.invalidConfiguration(error.localizedDescription)
        }

        let file: ExperimentFile
        do {
            file = try JSONDecoder().decode(ExperimentFile.self, from: data)
        } catch let error as DecodingError {
            throw ExperimentError.invalidConfiguration(describe(error))
        } catch {
            throw ExperimentError.invalidConfiguration(error.localizedDescription)
        }

        return try ConditionResolver.makePlan(from: file)
    }

    private static func describe(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        let path: [CodingKey]
        switch error {
        case .typeMismatch(_, let value), .valueNotFound(_, let value), .dataCorrupted(let value):
            context = value
            path = value.codingPath
        case .keyNotFound(let key, let value):
            context = value
            path = value.codingPath + [key]
        @unknown default:
            return error.localizedDescription
        }

        let jsonPath = path.reduce("$") { result, key in
            key.intValue.map { "\(result)[\($0)]" } ?? "\(result).\(key.stringValue)"
        }
        return "\(jsonPath): \(context.debugDescription)"
    }
}

enum ExperimentError: LocalizedError {
    case missingConfiguration
    case unreadableConfiguration(Error)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "The bundled experiment.json file is missing."
        case .unreadableConfiguration(let error):
            return "experiment.json couldn't be read: \(error.localizedDescription)"
        case .invalidConfiguration(let message):
            return "experiment.json is invalid: \(message)"
        }
    }
}

private struct ExperimentFile: Decodable {
    let schemaVersion: Int
    let conditions: [ConditionDefinition]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case conditions
    }
}

private enum InheritedField<Value> {
    case inherited
    case null
    case value(Value)
}

private enum RandomSeedSpecification: Equatable {
    case shuffle
    case fixed(UInt64)
    case list([UInt64])
}

extension RandomSeedSpecification: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(UInt64.self) {
            self = .fixed(value)
        } else if let values = try? container.decode([UInt64].self) {
            self = .list(values)
        } else {
            let keyword = try container.decode(String.self)
            guard keyword == "shuffle" else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an unsigned integer, an integer array, or the string ‘shuffle’."
                )
            }
            self = .shuffle
        }
    }
}

private struct DigitPatch: Decodable {
    let heightDegrees: Float?
    let fontName: String?
    let rgb: RGB?

    private enum CodingKeys: String, CodingKey {
        case heightDegrees = "height_degrees"
        case fontName = "font_name"
        case rgb
    }
}

private struct BoxPatch: Decodable {
    let widthDegrees: Float?
    let heightDegrees: Float?
    let strokeDegrees: Float?
    let fillRGB: RGB?
    let strokeRGB: RGB?
    let numberHorizontal: Int?
    let numberVertical: Int?

    private enum CodingKeys: String, CodingKey {
        case widthDegrees = "width_degrees"
        case heightDegrees = "height_degrees"
        case strokeDegrees = "stroke_degrees"
        case fillRGB = "fill_rgb"
        case strokeRGB = "stroke_rgb"
        case numberHorizontal = "number_horizontal"
        case numberVertical = "number_vertical"
    }
}

private struct FOVPatch: Decodable {
    let eye: StimulusEye?
    let mode: DisplayMode?
    let peakOpacity: Float?
    let widthDegrees: Float?
    let heightDegrees: Float?
    let horizontalOffsetDegrees: Float?
    let verticalOffsetDegrees: Float?
    let backgroundRGB: RGB?
    let borderStrokeArcmin: Float?
    let borderRGB: RGB?
    let distanceMeters: Float?

    private enum CodingKeys: String, CodingKey {
        case eye, mode
        case peakOpacity = "peak_opacity"
        case widthDegrees = "width_degrees"
        case heightDegrees = "height_degrees"
        case horizontalOffsetDegrees = "horizontal_offset_degrees"
        case verticalOffsetDegrees = "vertical_offset_degrees"
        case backgroundRGB = "background_rgb"
        case borderStrokeArcmin = "border_stroke_arcmin"
        case borderRGB = "border_rgb"
        case distanceMeters = "distance_meters"
    }
}

private struct SpeechPatch: Decodable {
    let aliases: [String: [String]]?
}

private struct ConditionDefinition: Decodable {
    let name: String
    let inherits: InheritedField<String>
    let blockNumber: InheritedField<Int>
    let repeats: InheritedField<Int>
    let randomSeed: InheritedField<RandomSeedSpecification>
    let digits: DigitPatch?
    let boxes: BoxPatch?
    let fov: FOVPatch?
    let speech: SpeechPatch?

    private enum CodingKeys: String, CodingKey {
        case name, inherits, repeats
        case randomSeed = "random_seed"
        case blockNumber = "block_nr"
        case digits, boxes, fov, speech
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        inherits = try Self.decodeField(String.self, key: .inherits, from: container)
        blockNumber = try Self.decodeField(Int.self, key: .blockNumber, from: container)
        repeats = try Self.decodeField(Int.self, key: .repeats, from: container)
        randomSeed = try Self.decodeField(
            RandomSeedSpecification.self,
            key: .randomSeed,
            from: container
        )
        digits = try container.decodeIfPresent(DigitPatch.self, forKey: .digits)
        boxes = try container.decodeIfPresent(BoxPatch.self, forKey: .boxes)
        fov = try container.decodeIfPresent(FOVPatch.self, forKey: .fov)
        speech = try container.decodeIfPresent(SpeechPatch.self, forKey: .speech)
    }

    private static func decodeField<T: Decodable>(
        _ type: T.Type,
        key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> InheritedField<T> {
        guard container.contains(key) else { return .inherited }
        guard try !container.decodeNil(forKey: key) else { return .null }
        return .value(try container.decode(type, forKey: key))
    }
}

private struct ResolvedConditionPatch {
    var blockNumber: Int?
    var repeats: Int?
    var randomSeed: RandomSeedSpecification?
    var digits = ResolvedDigits()
    var boxes = ResolvedBoxes()
    var fov = ResolvedFOV()
    var aliases: [String: [String]] = [:]

    mutating func apply(_ definition: ConditionDefinition) {
        blockNumber = definition.blockNumber.applying(to: blockNumber)
        repeats = definition.repeats.applying(to: repeats)
        randomSeed = definition.randomSeed.applying(to: randomSeed)

        if let patch = definition.digits {
            digits.heightDegrees = patch.heightDegrees ?? digits.heightDegrees
            digits.fontName = patch.fontName ?? digits.fontName
            digits.rgb = patch.rgb ?? digits.rgb
        }
        if let patch = definition.boxes {
            boxes.widthDegrees = patch.widthDegrees ?? boxes.widthDegrees
            boxes.heightDegrees = patch.heightDegrees ?? boxes.heightDegrees
            boxes.strokeDegrees = patch.strokeDegrees ?? boxes.strokeDegrees
            boxes.fillRGB = patch.fillRGB ?? boxes.fillRGB
            boxes.strokeRGB = patch.strokeRGB ?? boxes.strokeRGB
            boxes.numberHorizontal = patch.numberHorizontal ?? boxes.numberHorizontal
            boxes.numberVertical = patch.numberVertical ?? boxes.numberVertical
        }
        if let patch = definition.fov {
            fov.eye = patch.eye ?? fov.eye
            fov.mode = patch.mode ?? fov.mode
            fov.peakOpacity = patch.peakOpacity ?? fov.peakOpacity
            fov.widthDegrees = patch.widthDegrees ?? fov.widthDegrees
            fov.heightDegrees = patch.heightDegrees ?? fov.heightDegrees
            fov.horizontalOffsetDegrees = patch.horizontalOffsetDegrees ?? fov.horizontalOffsetDegrees
            fov.verticalOffsetDegrees = patch.verticalOffsetDegrees ?? fov.verticalOffsetDegrees
            fov.backgroundRGB = patch.backgroundRGB ?? fov.backgroundRGB
            fov.borderStrokeArcmin = patch.borderStrokeArcmin ?? fov.borderStrokeArcmin
            fov.borderRGB = patch.borderRGB ?? fov.borderRGB
            fov.distanceMeters = patch.distanceMeters ?? fov.distanceMeters
        }
        if let patch = definition.speech?.aliases {
            aliases.merge(patch) { _, child in child }
        }
    }
}

private struct ResolvedDigits {
    var heightDegrees: Float?
    var fontName: String?
    var rgb: RGB?
}

private struct ResolvedBoxes {
    var widthDegrees: Float?
    var heightDegrees: Float?
    var strokeDegrees: Float?
    var fillRGB: RGB?
    var strokeRGB: RGB?
    var numberHorizontal: Int?
    var numberVertical: Int?
}

private struct ResolvedFOV {
    var eye: StimulusEye?
    var mode: DisplayMode?
    var peakOpacity: Float?
    var widthDegrees: Float?
    var heightDegrees: Float?
    var horizontalOffsetDegrees: Float?
    var verticalOffsetDegrees: Float?
    var backgroundRGB: RGB?
    var borderStrokeArcmin: Float?
    var borderRGB: RGB?
    var distanceMeters: Float?
}

private extension InheritedField {
    func applying(to inheritedValue: Value?) -> Value? {
        switch self {
        case .inherited: inheritedValue
        case .null: nil
        case .value(let value): value
        }
    }
}

private struct ExpandedCondition {
    let name: String
    let blockNumber: Int
    let seed: UInt64
    let patch: ResolvedConditionPatch
}

private enum ConditionResolver {
    static let generatedName = "__condition_nr__"
    static let maximumTrialCount = 10_000

    static func makePlan(from file: ExperimentFile) throws -> ExperimentPlan {
        guard file.schemaVersion == 5 else {
            throw ExperimentError.invalidConfiguration(
                "schema_version \(file.schemaVersion) is unsupported; this app requires version 5."
            )
        }
        guard !file.conditions.isEmpty else {
            throw ExperimentError.invalidConfiguration("conditions must contain at least the master condition.")
        }

        try validateDefinitionNames(file.conditions)
        try validateMaster(file.conditions[0])

        let namedDefinitions = Dictionary(
            uniqueKeysWithValues: file.conditions
                .filter { $0.name != generatedName }
                .map { ($0.name, $0) }
        )
        var cache: [String: ResolvedConditionPatch] = [:]
        var expanded: [ExpandedCondition] = []

        for definition in file.conditions {
            let patch = try resolve(
                definition,
                namedDefinitions: namedDefinitions,
                cache: &cache,
                path: []
            )
            try validateResolved(patch, definitionName: definition.name)

            let repeats = patch.repeats!
            guard repeats >= 0 else {
                throw invalid(definition.name, "repeats must be zero or greater.")
            }
            guard repeats <= maximumTrialCount else {
                throw invalid(definition.name, "repeats may not exceed \(maximumTrialCount).")
            }
            if definition.name == generatedName, repeats == 0 {
                throw invalid(definition.name, "is a generated condition definition and therefore requires repeats greater than zero.")
            }
            guard repeats > 0 else { continue }
            guard let blockNumber = patch.blockNumber, blockNumber > 0 else {
                throw invalid(definition.name, "a condition with repeats greater than zero requires block_nr >= 1.")
            }
            guard let seedSpecification = patch.randomSeed else {
                throw invalid(definition.name, "a condition with repeats greater than zero requires random_seed.")
            }
            if definition.name != generatedName, repeats > 1 {
                throw invalid(
                    definition.name,
                    "a literal condition name may only be instantiated once; use \(generatedName) when repeats is greater than one."
                )
            }

            let seeds = try expandSeeds(
                seedSpecification,
                repeats: repeats,
                definitionName: definition.name
            )
            for seed in seeds {
                guard expanded.count < maximumTrialCount else {
                    throw ExperimentError.invalidConfiguration(
                        "The expanded experiment may contain at most \(maximumTrialCount) trials."
                    )
                }
                let conditionName = definition.name == generatedName
                    ? "condition\(expanded.count + 1)"
                    : definition.name
                expanded.append(
                    .init(
                        name: conditionName,
                        blockNumber: blockNumber,
                        seed: seed,
                        patch: patch
                    )
                )
            }
        }

        guard !expanded.isEmpty else {
            throw ExperimentError.invalidConfiguration(
                "At least one condition must have repeats greater than zero."
            )
        }
        guard Set(expanded.map(\.name)).count == expanded.count else {
            throw ExperimentError.invalidConfiguration(
                "Expanded condition names must be unique."
            )
        }

        try validateBlocks(expanded.map(\.blockNumber))
        let ordered = randomizedWithinBlocks(expanded)
        let trials = try ordered.enumerated().map { offset, condition in
            let configuration = try makeConfiguration(from: condition)
            return ScheduledTrial(
                trialNumber: offset + 1,
                conditionName: condition.name,
                blockNumber: condition.blockNumber,
                configuration: configuration
            )
        }
        return ExperimentPlan(trials: trials)
    }

    private static func validateDefinitionNames(_ definitions: [ConditionDefinition]) throws {
        var literalNames = Set<String>()
        for (index, definition) in definitions.enumerated() {
            let name = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name == definition.name else {
                throw ExperimentError.invalidConfiguration(
                    "conditions[\(index)].name must be nonempty and have no leading or trailing whitespace."
                )
            }
            if name.hasPrefix("__"), name != generatedName {
                throw ExperimentError.invalidConfiguration(
                    "conditions[\(index)].name ‘\(name)’ is reserved; the only supported reserved name is \(generatedName)."
                )
            }
            guard name == generatedName || literalNames.insert(name).inserted else {
                throw ExperimentError.invalidConfiguration("Condition name ‘\(name)’ is defined more than once.")
            }
            guard definition.inherits.isSpecified else {
                throw invalid(name, "inherits must be explicitly present.")
            }
        }
    }

    private static func validateMaster(_ master: ConditionDefinition) throws {
        guard master.name == "master" else {
            throw ExperimentError.invalidConfiguration("The first condition must be named ‘master’.")
        }
        guard master.inherits.isNull else {
            throw invalid("master", "inherits must be null.")
        }
        guard master.blockNumber.isNull else {
            throw invalid("master", "block_nr must be explicitly null.")
        }
        guard case .value(0) = master.repeats else {
            throw invalid("master", "repeats must be explicitly set to 0.")
        }
        guard master.randomSeed.isNull else {
            throw invalid("master", "random_seed must be explicitly null.")
        }
    }

    private static func resolve(
        _ definition: ConditionDefinition,
        namedDefinitions: [String: ConditionDefinition],
        cache: inout [String: ResolvedConditionPatch],
        path: [String]
    ) throws -> ResolvedConditionPatch {
        if definition.name != generatedName, let cached = cache[definition.name] {
            return cached
        }
        guard !path.contains(definition.name) else {
            throw invalid(definition.name, "inheritance cycle: \((path + [definition.name]).joined(separator: " → ")).")
        }

        var result = ResolvedConditionPatch()
        switch definition.inherits {
        case .inherited:
            throw invalid(definition.name, "inherits must be explicitly present.")
        case .null:
            guard definition.name == "master" else {
                throw invalid(definition.name, "only master may inherit null.")
            }
        case .value(let parentName):
            guard parentName != generatedName else {
                throw invalid(definition.name, "cannot inherit from the generated name \(generatedName).")
            }
            guard let parent = namedDefinitions[parentName] else {
                throw invalid(definition.name, "inherits unknown condition ‘\(parentName)’.")
            }
            result = try resolve(
                parent,
                namedDefinitions: namedDefinitions,
                cache: &cache,
                path: path + [definition.name]
            )
        }
        result.apply(definition)
        if definition.name != generatedName {
            cache[definition.name] = result
        }
        return result
    }

    private static func validateResolved(
        _ patch: ResolvedConditionPatch,
        definitionName: String
    ) throws {
        func missing(_ name: String) throws -> Never {
            throw invalid(definitionName, "does not resolve parameter \(name); master must define every parameter.")
        }
        guard patch.repeats != nil else { try missing("repeats") }
        guard let digitHeight = patch.digits.heightDegrees else { try missing("digits.height_degrees") }
        guard let fontName = patch.digits.fontName else { try missing("digits.font_name") }
        guard patch.digits.rgb != nil else { try missing("digits.rgb") }
        guard let boxWidth = patch.boxes.widthDegrees else { try missing("boxes.width_degrees") }
        guard let boxHeight = patch.boxes.heightDegrees else { try missing("boxes.height_degrees") }
        guard let boxStroke = patch.boxes.strokeDegrees else { try missing("boxes.stroke_degrees") }
        guard patch.boxes.fillRGB != nil else { try missing("boxes.fill_rgb") }
        guard patch.boxes.strokeRGB != nil else { try missing("boxes.stroke_rgb") }
        guard let columns = patch.boxes.numberHorizontal else { try missing("boxes.number_horizontal") }
        guard let rows = patch.boxes.numberVertical else { try missing("boxes.number_vertical") }
        guard patch.fov.eye != nil else { try missing("fov.eye") }
        guard patch.fov.mode != nil else { try missing("fov.mode") }
        guard let peakOpacity = patch.fov.peakOpacity else { try missing("fov.peak_opacity") }
        guard let fovWidth = patch.fov.widthDegrees else { try missing("fov.width_degrees") }
        guard let fovHeight = patch.fov.heightDegrees else { try missing("fov.height_degrees") }
        guard let horizontalOffset = patch.fov.horizontalOffsetDegrees else { try missing("fov.horizontal_offset_degrees") }
        guard let verticalOffset = patch.fov.verticalOffsetDegrees else { try missing("fov.vertical_offset_degrees") }
        guard patch.fov.backgroundRGB != nil else { try missing("fov.background_rgb") }
        guard let borderStroke = patch.fov.borderStrokeArcmin else { try missing("fov.border_stroke_arcmin") }
        guard patch.fov.borderRGB != nil else { try missing("fov.border_rgb") }
        guard let distance = patch.fov.distanceMeters else { try missing("fov.distance_meters") }

        let requiredDigitKeys = Set((0...9).map(String.init))
        guard Set(patch.aliases.keys) == requiredDigitKeys else {
            throw invalid(definitionName, "speech.aliases must resolve exactly the keys 0 through 9.")
        }
        var aliasOwners: [String: String] = [:]
        for digit in requiredDigitKeys.sorted() {
            guard let aliases = patch.aliases[digit], !aliases.isEmpty else {
                throw invalid(definitionName, "speech.aliases.\(digit) must contain at least one spoken form.")
            }
            var aliasesForDigit = Set<String>()
            for alias in aliases {
                let normalized = SpeechConfiguration.normalize(alias)
                guard !normalized.isEmpty,
                      normalized.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else {
                    throw invalid(
                        definitionName,
                        "speech.aliases.\(digit) contains ‘\(alias)’; aliases must be single words containing letters only."
                    )
                }
                guard aliasesForDigit.insert(normalized).inserted else {
                    throw invalid(definitionName, "speech.aliases.\(digit) contains duplicate alias ‘\(normalized)’.")
                }
                if let existing = aliasOwners[normalized], existing != digit {
                    throw invalid(definitionName, "speech alias ‘\(normalized)’ belongs to both \(existing) and \(digit).")
                }
                aliasOwners[normalized] = digit
            }
        }

        let positive: [(String, Float)] = [
            ("digits.height_degrees", digitHeight),
            ("boxes.width_degrees", boxWidth),
            ("boxes.height_degrees", boxHeight),
            ("fov.width_degrees", fovWidth),
            ("fov.height_degrees", fovHeight),
            ("fov.distance_meters", distance)
        ]
        for (name, value) in positive where !value.isFinite || value <= 0 {
            throw invalid(definitionName, "\(name) must be finite and greater than zero.")
        }
        let nonnegative: [(String, Float)] = [
            ("boxes.stroke_degrees", boxStroke),
            ("fov.border_stroke_arcmin", borderStroke)
        ]
        for (name, value) in nonnegative where !value.isFinite || value < 0 {
            throw invalid(definitionName, "\(name) must be finite and zero or greater.")
        }
        guard horizontalOffset.isFinite, verticalOffset.isFinite else {
            throw invalid(definitionName, "FOV offsets must be finite.")
        }
        guard peakOpacity.isFinite, (0...1).contains(peakOpacity) else {
            throw invalid(definitionName, "fov.peak_opacity must be between 0 and 1.")
        }
        guard columns >= 3, rows >= 3 else {
            throw invalid(definitionName, "the box grid must be at least 3 × 3.")
        }
        guard columns <= 254, rows <= 254 else {
            throw invalid(definitionName, "each box-grid dimension may be at most 254.")
        }
        guard boxStroke * 2 < min(boxWidth, boxHeight) else {
            throw invalid(definitionName, "boxes.stroke_degrees is too large for the boxes.")
        }
        guard borderStroke / 60 * 2 < min(fovWidth, fovHeight) else {
            throw invalid(definitionName, "fov.border_stroke_arcmin is too large for the FOV.")
        }
        guard boxWidth * Float(columns) <= fovWidth,
              boxHeight * Float(rows) <= fovHeight else {
            throw invalid(definitionName, "the centered box grid does not fit inside the FOV.")
        }
        let spaceAboveCenteredGrid = (fovHeight - boxHeight * Float(rows)) / 2
        guard spaceAboveCenteredGrid >= digitHeight * 1.5 else {
            throw invalid(
                definitionName,
                "the FOV needs at least 1.5 digit heights above the centered grid for the target cue."
            )
        }
        guard !fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid(definitionName, "digits.font_name must not be empty.")
        }
    }

    private static func expandSeeds(
        _ specification: RandomSeedSpecification,
        repeats: Int,
        definitionName: String
    ) throws -> [UInt64] {
        switch specification {
        case .shuffle:
            var generator = SystemRandomNumberGenerator()
            return (0..<repeats).map { _ in UInt64.random(in: .min ... .max, using: &generator) }
        case .fixed(let seed):
            return [UInt64](repeating: seed, count: repeats)
        case .list(let seeds):
            guard seeds.count == repeats else {
                throw invalid(
                    definitionName,
                    "random_seed contains \(seeds.count) values but repeats is \(repeats)."
                )
            }
            return seeds
        }
    }

    private static func validateBlocks(_ blocks: [Int]) throws {
        let uniqueBlocks = Set(blocks)
        guard let maximum = uniqueBlocks.max(),
              uniqueBlocks == Set(1...maximum) else {
            let actual = uniqueBlocks.sorted().map(String.init).joined(separator: ", ")
            throw ExperimentError.invalidConfiguration(
                "Instantiated block numbers must start at 1 and be consecutive without gaps; found [\(actual)]."
            )
        }
    }

    private static func randomizedWithinBlocks(
        _ conditions: [ExpandedCondition]
    ) -> [ExpandedCondition] {
        let maximumBlock = conditions.map(\.blockNumber).max()!
        var generator = SystemRandomNumberGenerator()
        return (1...maximumBlock).flatMap { block in
            conditions
                .filter { $0.blockNumber == block }
                .shuffled(using: &generator)
        }
    }

    private static func makeConfiguration(
        from condition: ExpandedCondition
    ) throws -> ExperimentConfiguration {
        let patch = condition.patch
        return ExperimentConfiguration(
            display: .init(
                mode: patch.fov.mode!,
                peakOpacity: patch.fov.peakOpacity!
            ),
            speech: .init(digitAliases: patch.aliases),
            stimulus: .init(
                eye: patch.fov.eye!,
                randomSeed: condition.seed,
                digitHeightArcmin: patch.digits.heightDegrees! * 60,
                digitFontName: patch.digits.fontName!,
                digitRGB: patch.digits.rgb!,
                digitBoxWidthArcmin: patch.boxes.widthDegrees! * 60,
                digitBoxHeightArcmin: patch.boxes.heightDegrees! * 60,
                digitBoxStrokeArcmin: patch.boxes.strokeDegrees! * 60,
                digitBoxFillRGB: patch.boxes.fillRGB!,
                digitBoxStrokeRGB: patch.boxes.strokeRGB!,
                numberOfDigitBoxesHorizontal: patch.boxes.numberHorizontal!,
                numberOfDigitBoxesVertical: patch.boxes.numberVertical!,
                fovWidthDegrees: patch.fov.widthDegrees!,
                fovHeightDegrees: patch.fov.heightDegrees!,
                fovHorizontalOffsetDegrees: patch.fov.horizontalOffsetDegrees!,
                fovVerticalOffsetDegrees: patch.fov.verticalOffsetDegrees!,
                fovBackgroundRGB: patch.fov.backgroundRGB!,
                fovBorderStrokeArcmin: patch.fov.borderStrokeArcmin!,
                fovBorderRGB: patch.fov.borderRGB!,
                distanceMeters: patch.fov.distanceMeters!
            )
        )
    }

    private static func invalid(_ condition: String, _ message: String) -> ExperimentError {
        .invalidConfiguration("condition ‘\(condition)’ \(message)")
    }
}

private extension InheritedField {
    var isSpecified: Bool {
        if case .inherited = self { return false }
        return true
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

private enum JSONShapeValidator {
    static func validate(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ExperimentError.invalidConfiguration("Malformed JSON: \(error.localizedDescription)")
        }
        let root = try dictionary(object, path: "$")
        try keys(root, allowed: ["schema_version", "conditions"], path: "$")
        guard let rawConditions = root["conditions"] as? [Any] else {
            throw invalid("$.conditions", "must be an array.")
        }
        for (index, rawCondition) in rawConditions.enumerated() {
            let path = "$.conditions[\(index)]"
            let condition = try dictionary(rawCondition, path: path)
            try keys(
                condition,
                allowed: ["name", "inherits", "block_nr", "repeats", "random_seed", "digits", "boxes", "fov", "speech"],
                path: path
            )
            try section(condition["digits"], path: "\(path).digits", allowed: ["height_degrees", "font_name", "rgb"])
            try section(
                condition["boxes"],
                path: "\(path).boxes",
                allowed: ["width_degrees", "height_degrees", "stroke_degrees", "fill_rgb", "stroke_rgb", "number_horizontal", "number_vertical"]
            )
            try section(
                condition["fov"],
                path: "\(path).fov",
                allowed: ["eye", "mode", "peak_opacity", "width_degrees", "height_degrees", "horizontal_offset_degrees", "vertical_offset_degrees", "background_rgb", "border_stroke_arcmin", "border_rgb", "distance_meters"]
            )
            if let rawSpeech = condition["speech"] {
                let speech = try dictionary(rawSpeech, path: "\(path).speech")
                try keys(speech, allowed: ["aliases"], path: "\(path).speech")
                if let rawAliases = speech["aliases"] {
                    let aliases = try dictionary(rawAliases, path: "\(path).speech.aliases")
                    try keys(aliases, allowed: Set((0...9).map(String.init)), path: "\(path).speech.aliases")
                }
            }
        }
    }

    private static func section(
        _ rawValue: Any?,
        path: String,
        allowed: Set<String>
    ) throws {
        guard let rawValue else { return }
        let value = try dictionary(rawValue, path: path)
        try keys(value, allowed: allowed, path: path)
    }

    private static func dictionary(_ value: Any, path: String) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw invalid(path, "must be an object.")
        }
        return dictionary
    }

    private static func keys(
        _ dictionary: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        let unknown = Set(dictionary.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw invalid(path, "contains unknown key(s): \(unknown.joined(separator: ", ")).")
        }
    }

    private static func invalid(_ path: String, _ message: String) -> ExperimentError {
        .invalidConfiguration("\(path) \(message)")
    }
}

private enum NumberGridGenerator {
    static func makeGrid(using config: StimulusConfiguration) -> NumberGrid {
        let rows = config.numberOfDigitBoxesVertical
        let columns = config.numberOfDigitBoxesHorizontal
        var random = SplitMix64(seed: config.randomSeed)
        let targetNumber = String(100 + random.nextInt(upperBound: 900))
        let number = Array(targetNumber.utf8)
        let orientations = NumberGrid.Orientation.allThatFit(
            numberLength: number.count,
            rows: rows,
            columns: columns
        )

        while true {
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

            guard findOccurrences(of: number, in: digits, rows: rows, columns: columns) == [placement] else {
                continue
            }

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
                verificationPlacement = .init(row: middleRow - 1, column: middleColumn, orientation: .vertical)
            case .vertical:
                verificationIndices = [middleColumn - 1, middleColumn, middleColumn + 1].map {
                    middleRow * columns + $0
                }
                verificationPlacement = .init(row: middleRow, column: middleColumn - 1, orientation: .horizontal)
            }
            let verificationDigits = verificationIndices.map { digits[$0] }
            guard findOccurrences(
                of: verificationDigits,
                in: digits,
                rows: rows,
                columns: columns
            ) == [verificationPlacement] else {
                continue
            }

            return NumberGrid(
                rows: rows,
                columns: columns,
                digits: digits,
                targetNumber: targetNumber,
                targetPlacement: placement,
                verificationCode: String(bytes: verificationDigits, encoding: .ascii)!
            )
        }
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
                    if number.indices.allSatisfy({ digits[row * columns + column + $0] == number[$0] }) {
                        matches.append(.init(row: row, column: column, orientation: .horizontal))
                    }
                }
            }
        }
        if number.count <= rows {
            for row in 0...(rows - number.count) {
                for column in 0..<columns {
                    if number.indices.allSatisfy({ digits[(row + $0) * columns + column] == number[$0] }) {
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
