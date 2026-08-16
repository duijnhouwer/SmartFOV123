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

enum DigitRandomMethod: String, Decodable, CaseIterable, Sendable {
    case flatDistribution = "flat_distribution"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let method = Self(rawValue: value) else {
            let allowed = Self.allCases.map(\.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid value ‘\(value)’; expected one of: \(allowed)."
            )
        }
        self = method
    }
}

enum TaskMode: Equatable, Sendable {
    case fixedNumberOfTrials
    case loopTrials(seconds: Int)

    var rawValue: String {
        switch self {
        case .fixedNumberOfTrials:
            return "fixed_number_of_trials"
        case .loopTrials(let seconds):
            return "loop_trials_\(seconds)_seconds"
        }
    }

    var durationSeconds: Int? {
        guard case .loopTrials(let seconds) = self else { return nil }
        return seconds
    }
}

extension TaskMode: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "fixed_number_of_trials" {
            self = .fixedNumberOfTrials
            return
        }

        let prefix = "loop_trials_"
        let suffix = "_seconds"
        guard value.hasPrefix(prefix), value.hasSuffix(suffix) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ‘fixed_number_of_trials’ or ‘loop_trials_<positive integer>_seconds’."
            )
        }
        let secondsText = value.dropFirst(prefix.count).dropLast(suffix.count)
        guard let seconds = Int(secondsText), seconds > 0,
              String(secondsText) == String(seconds) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A loop-trials task duration must be a canonical positive integer number of seconds."
            )
        }
        self = .loopTrials(seconds: seconds)
    }
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
    let digitRandomMethod: DigitRandomMethod

    let annotationHeightArcmin: Float
    let annotationFontName: String
    let annotationRGB: RGB

    let tileWidthArcmin: Float
    let tileHeightArcmin: Float
    let tileGutterArcmin: Float
    let tileCornerRadiusArcmin: Float
    let tileFillRGB: RGB
    let tileGutterRGB: RGB
    let numberOfTilesHorizontal: Int
    let numberOfTilesVertical: Int

    let surroundFillRGB: RGB
    let surroundInnerMarginRGB: RGB
    let surroundInnerMarginArcmin: Float
    let surroundInnerCornerRadiusArcmin: Float
    let surroundOuterCornerRadiusArcmin: Float

    let fovWidthDegrees: Float
    let fovHeightDegrees: Float
    let fovHorizontalOffsetDegrees: Float
    let fovVerticalOffsetDegrees: Float
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
    let randomSeed: UInt64
    let configuration: ExperimentConfiguration
    let grid: NumberGrid
}

struct ScheduledTrial: Sendable {
    let trialNumber: Int
    let conditionName: String
    let blockNumber: Int
    let configuration: ExperimentConfiguration

    func instantiate(trialNumber: Int? = nil) -> Experiment {
        let seed = configuration.stimulus.randomSeed
        return Experiment(
            trialNumber: trialNumber ?? self.trialNumber,
            conditionName: conditionName,
            blockNumber: blockNumber,
            randomSeed: seed,
            configuration: configuration,
            grid: NumberGridGenerator.makeGrid(
                using: configuration.stimulus,
                randomSeed: seed
            )
        )
    }
}

struct ExperimentPlan: Sendable {
    let protocolName: String
    let subjectNumberDigitCount: Int
    let instructions: String
    let debriefing: String
    let taskMode: TaskMode
    /// Compositor-layer configuration is fixed for the duration of a session,
    /// so this option applies consistently to every trial in the plan.
    let foveatedRendering: Bool
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
    let protocolName: String
    let subjectNumberDigitCount: Int
    let instructions: String
    let debriefing: String
    let taskMode: TaskMode
    let foveatedRendering: Bool?
    let conditions: [ConditionDefinition]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case protocolName = "protocol_name"
        case subjectNumberDigitCount = "subject_number_digit_count"
        case instructions
        case debriefing
        case taskMode = "task_mode"
        case foveatedRendering = "foveated_rendering"
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
    let randomMethod: DigitRandomMethod?

    private enum CodingKeys: String, CodingKey {
        case heightDegrees = "height_degrees"
        case fontName = "font_name"
        case rgb
        case randomMethod = "random_method"
    }
}

private struct AnnotationPatch: Decodable {
    let heightDegrees: Float?
    let fontName: String?
    let rgb: RGB?

    private enum CodingKeys: String, CodingKey {
        case heightDegrees = "height_degrees"
        case fontName = "font_name"
        case rgb
    }
}

private struct TilePatch: Decodable {
    let widthDegrees: Float?
    let heightDegrees: Float?
    let gutterDegrees: Float?
    let cornerRadiusDegrees: Float?
    let fillRGB: RGB?
    let gutterRGB: RGB?
    let numberHorizontal: Int?
    let numberVertical: Int?

    private enum CodingKeys: String, CodingKey {
        case widthDegrees = "width_degrees"
        case heightDegrees = "height_degrees"
        case gutterDegrees = "gutter_degrees"
        case cornerRadiusDegrees = "corner_radius_degrees"
        case fillRGB = "fill_rgb"
        case gutterRGB = "gutter_rgb"
        case numberHorizontal = "number_horizontal"
        case numberVertical = "number_vertical"
    }
}

private struct SurroundPatch: Decodable {
    let fillRGB: RGB?
    let innerMarginRGB: RGB?
    let innerMarginDegrees: Float?
    let innerCornerRadiusDegrees: Float?
    let outerCornerRadiusDegrees: Float?

    private enum CodingKeys: String, CodingKey {
        case fillRGB = "fill_rgb"
        case innerMarginRGB = "inner_margin_rgb"
        case innerMarginDegrees = "inner_margin_degrees"
        case innerCornerRadiusDegrees = "inner_corner_radius_degrees"
        case outerCornerRadiusDegrees = "outer_corner_radius_degrees"
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
    let distanceMeters: Float?

    private enum CodingKeys: String, CodingKey {
        case eye, mode
        case peakOpacity = "peak_opacity"
        case widthDegrees = "width_degrees"
        case heightDegrees = "height_degrees"
        case horizontalOffsetDegrees = "horizontal_offset_degrees"
        case verticalOffsetDegrees = "vertical_offset_degrees"
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
    let annotation: AnnotationPatch?
    let tiles: TilePatch?
    let surround: SurroundPatch?
    let fov: FOVPatch?
    let speech: SpeechPatch?

    private enum CodingKeys: String, CodingKey {
        case name, inherits, repeats
        case randomSeed = "random_seed"
        case blockNumber = "block_nr"
        case digits, annotation, tiles, surround, fov, speech
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
        annotation = try container.decodeIfPresent(AnnotationPatch.self, forKey: .annotation)
        tiles = try container.decodeIfPresent(TilePatch.self, forKey: .tiles)
        surround = try container.decodeIfPresent(SurroundPatch.self, forKey: .surround)
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
    var annotation = ResolvedAnnotation()
    var tiles = ResolvedTiles()
    var surround = ResolvedSurround()
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
            digits.randomMethod = patch.randomMethod ?? digits.randomMethod
        }
        if let patch = definition.annotation {
            annotation.heightDegrees = patch.heightDegrees ?? annotation.heightDegrees
            annotation.fontName = patch.fontName ?? annotation.fontName
            annotation.rgb = patch.rgb ?? annotation.rgb
        }
        if let patch = definition.tiles {
            tiles.widthDegrees = patch.widthDegrees ?? tiles.widthDegrees
            tiles.heightDegrees = patch.heightDegrees ?? tiles.heightDegrees
            tiles.gutterDegrees = patch.gutterDegrees ?? tiles.gutterDegrees
            tiles.cornerRadiusDegrees = patch.cornerRadiusDegrees ?? tiles.cornerRadiusDegrees
            tiles.fillRGB = patch.fillRGB ?? tiles.fillRGB
            tiles.gutterRGB = patch.gutterRGB ?? tiles.gutterRGB
            tiles.numberHorizontal = patch.numberHorizontal ?? tiles.numberHorizontal
            tiles.numberVertical = patch.numberVertical ?? tiles.numberVertical
        }
        if let patch = definition.surround {
            surround.fillRGB = patch.fillRGB ?? surround.fillRGB
            surround.innerMarginRGB = patch.innerMarginRGB ?? surround.innerMarginRGB
            surround.innerMarginDegrees = patch.innerMarginDegrees ?? surround.innerMarginDegrees
            surround.innerCornerRadiusDegrees = patch.innerCornerRadiusDegrees
                ?? surround.innerCornerRadiusDegrees
            surround.outerCornerRadiusDegrees = patch.outerCornerRadiusDegrees
                ?? surround.outerCornerRadiusDegrees
        }
        if let patch = definition.fov {
            fov.eye = patch.eye ?? fov.eye
            fov.mode = patch.mode ?? fov.mode
            fov.peakOpacity = patch.peakOpacity ?? fov.peakOpacity
            fov.widthDegrees = patch.widthDegrees ?? fov.widthDegrees
            fov.heightDegrees = patch.heightDegrees ?? fov.heightDegrees
            fov.horizontalOffsetDegrees = patch.horizontalOffsetDegrees ?? fov.horizontalOffsetDegrees
            fov.verticalOffsetDegrees = patch.verticalOffsetDegrees ?? fov.verticalOffsetDegrees
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
    var randomMethod: DigitRandomMethod?
}

private struct ResolvedAnnotation {
    var heightDegrees: Float?
    var fontName: String?
    var rgb: RGB?
}

private struct ResolvedTiles {
    var widthDegrees: Float?
    var heightDegrees: Float?
    var gutterDegrees: Float?
    var cornerRadiusDegrees: Float?
    var fillRGB: RGB?
    var gutterRGB: RGB?
    var numberHorizontal: Int?
    var numberVertical: Int?
}

private struct ResolvedSurround {
    var fillRGB: RGB?
    var innerMarginRGB: RGB?
    var innerMarginDegrees: Float?
    var innerCornerRadiusDegrees: Float?
    var outerCornerRadiusDegrees: Float?
}

private struct ResolvedFOV {
    var eye: StimulusEye?
    var mode: DisplayMode?
    var peakOpacity: Float?
    var widthDegrees: Float?
    var heightDegrees: Float?
    var horizontalOffsetDegrees: Float?
    var verticalOffsetDegrees: Float?
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
        let protocolName = file.protocolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !protocolName.isEmpty, protocolName == file.protocolName else {
            throw ExperimentError.invalidConfiguration(
                "protocol_name must be nonempty and have no leading or trailing whitespace."
            )
        }
        guard (1...12).contains(file.subjectNumberDigitCount) else {
            throw ExperimentError.invalidConfiguration(
                "subject_number_digit_count must be between 1 and 12."
            )
        }
        let instructions = file.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instructions.isEmpty, instructions == file.instructions else {
            throw ExperimentError.invalidConfiguration(
                "instructions must be nonempty and have no leading or trailing whitespace."
            )
        }
        let debriefing = file.debriefing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !debriefing.isEmpty, debriefing == file.debriefing else {
            throw ExperimentError.invalidConfiguration(
                "debriefing must be nonempty and have no leading or trailing whitespace."
            )
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
        let gridSizes = Set(trials.map { trial in
            let stimulus = trial.configuration.stimulus
            return "\(stimulus.numberOfTilesHorizontal)x\(stimulus.numberOfTilesVertical)"
        })
        let gridSizeDescription = gridSizes.sorted().joined(separator: " or ")
        let resolvedInstructions = instructions
            .replacingOccurrences(
                of: "<NUMBEROFTRIALS>",
                with: String(trials.count)
            )
            .replacingOccurrences(
                of: "<GRIDSIZE>",
                with: gridSizeDescription
            )
        return ExperimentPlan(
            protocolName: protocolName,
            subjectNumberDigitCount: file.subjectNumberDigitCount,
            instructions: resolvedInstructions,
            debriefing: debriefing,
            taskMode: file.taskMode,
            foveatedRendering: file.foveatedRendering ?? true,
            trials: trials
        )
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
        guard patch.digits.randomMethod != nil else { try missing("digits.random_method") }
        guard let annotationHeight = patch.annotation.heightDegrees else {
            try missing("annotation.height_degrees")
        }
        guard let annotationFontName = patch.annotation.fontName else {
            try missing("annotation.font_name")
        }
        guard patch.annotation.rgb != nil else { try missing("annotation.rgb") }
        guard let tileWidth = patch.tiles.widthDegrees else { try missing("tiles.width_degrees") }
        guard let tileHeight = patch.tiles.heightDegrees else { try missing("tiles.height_degrees") }
        guard let tileGutter = patch.tiles.gutterDegrees else { try missing("tiles.gutter_degrees") }
        guard let tileCornerRadius = patch.tiles.cornerRadiusDegrees else { try missing("tiles.corner_radius_degrees") }
        guard patch.tiles.fillRGB != nil else { try missing("tiles.fill_rgb") }
        guard patch.tiles.gutterRGB != nil else { try missing("tiles.gutter_rgb") }
        guard let columns = patch.tiles.numberHorizontal else { try missing("tiles.number_horizontal") }
        guard let rows = patch.tiles.numberVertical else { try missing("tiles.number_vertical") }
        guard patch.surround.fillRGB != nil else { try missing("surround.fill_rgb") }
        guard patch.surround.innerMarginRGB != nil else { try missing("surround.inner_margin_rgb") }
        guard let surroundInnerMargin = patch.surround.innerMarginDegrees else {
            try missing("surround.inner_margin_degrees")
        }
        guard let surroundInnerCornerRadius = patch.surround.innerCornerRadiusDegrees else {
            try missing("surround.inner_corner_radius_degrees")
        }
        guard let surroundOuterCornerRadius = patch.surround.outerCornerRadiusDegrees else {
            try missing("surround.outer_corner_radius_degrees")
        }
        guard patch.fov.eye != nil else { try missing("fov.eye") }
        guard patch.fov.mode != nil else { try missing("fov.mode") }
        guard let peakOpacity = patch.fov.peakOpacity else { try missing("fov.peak_opacity") }
        guard let fovWidth = patch.fov.widthDegrees else { try missing("fov.width_degrees") }
        guard let fovHeight = patch.fov.heightDegrees else { try missing("fov.height_degrees") }
        guard let horizontalOffset = patch.fov.horizontalOffsetDegrees else { try missing("fov.horizontal_offset_degrees") }
        guard let verticalOffset = patch.fov.verticalOffsetDegrees else { try missing("fov.vertical_offset_degrees") }
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
            ("annotation.height_degrees", annotationHeight),
            ("tiles.width_degrees", tileWidth),
            ("tiles.height_degrees", tileHeight),
            ("fov.width_degrees", fovWidth),
            ("fov.height_degrees", fovHeight),
            ("fov.distance_meters", distance)
        ]
        for (name, value) in positive where !value.isFinite || value <= 0 {
            throw invalid(definitionName, "\(name) must be finite and greater than zero.")
        }
        let nonnegative: [(String, Float)] = [
            ("tiles.gutter_degrees", tileGutter),
            ("tiles.corner_radius_degrees", tileCornerRadius),
            ("surround.inner_margin_degrees", surroundInnerMargin),
            ("surround.inner_corner_radius_degrees", surroundInnerCornerRadius),
            ("surround.outer_corner_radius_degrees", surroundOuterCornerRadius)
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
        guard columns >= 4 else {
            throw invalid(definitionName, "tiles.number_horizontal must be at least 4.")
        }
        guard rows >= 4 else {
            throw invalid(definitionName, "tiles.number_vertical must be at least 4.")
        }
        guard columns <= 254, rows <= 254 else {
            throw invalid(definitionName, "each tile-grid dimension may be at most 254.")
        }
        guard tileGutter < min(tileWidth, tileHeight) else {
            throw invalid(definitionName, "tiles.gutter_degrees is too large for the tiles.")
        }
        guard tileCornerRadius * 2 < min(tileWidth, tileHeight) else {
            throw invalid(definitionName, "tiles.corner_radius_degrees is too large for the tiles.")
        }
        let gridWidth = tileWidth * Float(columns)
            + tileGutter * Float(columns - 1) + surroundInnerMargin * 2
        let gridHeight = tileHeight * Float(rows)
            + tileGutter * Float(rows - 1) + surroundInnerMargin * 2
        guard gridWidth <= fovWidth, gridHeight <= fovHeight else {
            throw invalid(definitionName, "the centered tile grid does not fit inside the FOV.")
        }
        guard surroundInnerCornerRadius * 2 <= min(gridWidth, gridHeight),
              surroundOuterCornerRadius * 2 <= min(fovWidth, fovHeight) else {
            throw invalid(definitionName, "surround corner radius is too large.")
        }
        let spaceAboveCenteredGrid = (fovHeight - gridHeight) / 2
        let headingHeight = max(digitHeight, annotationHeight)
        guard spaceAboveCenteredGrid >= headingHeight * 1.5 else {
            let targetCueClearance = headingHeight * 1.5
            let minimumFOVHeight = gridHeight + targetCueClearance * 2
            throw invalid(
                definitionName,
                String(
                    format: "fov.height_degrees %.2f° leaves %.2f° above the centered tile grid, but the target cue needs %.2f°. Increase fov.height_degrees to at least %.2f°, reduce the tile grid, or reduce digits.height_degrees.",
                    fovHeight,
                    spaceAboveCenteredGrid,
                    targetCueClearance,
                    minimumFOVHeight
                )
            )
        }
        guard !fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid(definitionName, "digits.font_name must not be empty.")
        }
        guard !annotationFontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid(definitionName, "annotation.font_name must not be empty.")
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
                digitRandomMethod: patch.digits.randomMethod!,
                annotationHeightArcmin: patch.annotation.heightDegrees! * 60,
                annotationFontName: patch.annotation.fontName!,
                annotationRGB: patch.annotation.rgb!,
                tileWidthArcmin: patch.tiles.widthDegrees! * 60,
                tileHeightArcmin: patch.tiles.heightDegrees! * 60,
                tileGutterArcmin: patch.tiles.gutterDegrees! * 60,
                tileCornerRadiusArcmin: patch.tiles.cornerRadiusDegrees! * 60,
                tileFillRGB: patch.tiles.fillRGB!,
                tileGutterRGB: patch.tiles.gutterRGB!,
                numberOfTilesHorizontal: patch.tiles.numberHorizontal!,
                numberOfTilesVertical: patch.tiles.numberVertical!,
                surroundFillRGB: patch.surround.fillRGB!,
                surroundInnerMarginRGB: patch.surround.innerMarginRGB!,
                surroundInnerMarginArcmin: patch.surround.innerMarginDegrees! * 60,
                surroundInnerCornerRadiusArcmin: patch.surround.innerCornerRadiusDegrees! * 60,
                surroundOuterCornerRadiusArcmin: patch.surround.outerCornerRadiusDegrees! * 60,
                fovWidthDegrees: patch.fov.widthDegrees!,
                fovHeightDegrees: patch.fov.heightDegrees!,
                fovHorizontalOffsetDegrees: patch.fov.horizontalOffsetDegrees!,
                fovVerticalOffsetDegrees: patch.fov.verticalOffsetDegrees!,
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
        try keys(
            root,
            allowed: [
                "schema_version", "protocol_name", "subject_number_digit_count",
                "instructions", "debriefing", "foveated_rendering", "task_mode", "conditions"
            ],
            path: "$"
        )
        guard let rawConditions = root["conditions"] as? [Any] else {
            throw invalid("$.conditions", "must be an array.")
        }
        for (index, rawCondition) in rawConditions.enumerated() {
            let path = "$.conditions[\(index)]"
            let condition = try dictionary(rawCondition, path: path)
            try keys(
                condition,
                allowed: ["name", "inherits", "block_nr", "repeats", "random_seed", "digits", "annotation", "tiles", "surround", "fov", "speech"],
                path: path
            )
            try section(
                condition["digits"],
                path: "\(path).digits",
                allowed: ["height_degrees", "font_name", "rgb", "random_method"]
            )
            try section(
                condition["annotation"],
                path: "\(path).annotation",
                allowed: ["height_degrees", "font_name", "rgb"]
            )
            try section(
                condition["tiles"],
                path: "\(path).tiles",
                allowed: ["width_degrees", "height_degrees", "gutter_degrees", "corner_radius_degrees", "fill_rgb", "gutter_rgb", "number_horizontal", "number_vertical"]
            )
            try section(
                condition["surround"],
                path: "\(path).surround",
                allowed: ["fill_rgb", "inner_margin_rgb", "inner_margin_degrees", "inner_corner_radius_degrees", "outer_corner_radius_degrees"]
            )
            try section(
                condition["fov"],
                path: "\(path).fov",
                allowed: ["eye", "mode", "peak_opacity", "width_degrees", "height_degrees", "horizontal_offset_degrees", "vertical_offset_degrees", "distance_meters"]
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
    static func makeGrid(
        using config: StimulusConfiguration,
        randomSeed: UInt64
    ) -> NumberGrid {
        let rows = config.numberOfTilesVertical
        let columns = config.numberOfTilesHorizontal
        var random = SplitMix64(seed: randomSeed)

        while true {
            let targetNumber = makeTargetNumber(using: &random)
            let number = Array(targetNumber.utf8)
            let orientations = NumberGrid.Orientation.allThatFit(
                numberLength: number.count,
                rows: rows,
                columns: columns
            )
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

            var availableDigits = makeDigitPool(
                count: rows * columns,
                method: config.digitRandomMethod,
                using: &random
            )
            for digit in number {
                let poolIndex = availableDigits.firstIndex(of: digit)!
                availableDigits.remove(at: poolIndex)
            }
            shuffle(&availableDigits, using: &random)

            var digits = [UInt8](repeating: 0, count: rows * columns)
            var targetIndices = Set<Int>()
            for (offset, digit) in number.enumerated() {
                let row = placement.row + (orientation == .vertical ? offset : 0)
                let column = placement.column + (orientation == .horizontal ? offset : 0)
                let index = row * columns + column
                digits[index] = digit
                targetIndices.insert(index)
            }
            var availableIndex = 0
            for index in digits.indices where !targetIndices.contains(index) {
                digits[index] = availableDigits[availableIndex]
                availableIndex += 1
            }

            guard findOccurrences(of: number, in: digits, rows: rows, columns: columns) == [placement] else {
                continue
            }

            let middleOffset = number.count / 2
            let middleRow = placement.row + (orientation == .vertical ? middleOffset : 0)
            let middleColumn = placement.column + (orientation == .horizontal ? middleOffset : 0)
            let verificationIndices: [Int]
            switch orientation {
            case .horizontal:
                verificationIndices = [middleRow - 1, middleRow, middleRow + 1].map {
                    $0 * columns + middleColumn
                }
            case .vertical:
                verificationIndices = [middleColumn - 1, middleColumn, middleColumn + 1].map {
                    middleRow * columns + $0
                }
            }
            let verificationDigits = verificationIndices.map { digits[$0] }

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

    private static func makeTargetNumber(using random: inout SplitMix64) -> String {
        while true {
            let value = 12 + random.nextInt(upperBound: 976)
            let number = String(format: "%03d", value)
            guard Set(number).count == 3 else { continue }
            return number
        }
    }

    private static func makeDigitPool(
        count: Int,
        method: DigitRandomMethod,
        using random: inout SplitMix64
    ) -> [UInt8] {
        switch method {
        case .flatDistribution:
            let copiesPerDigit = count / 10
            var digits = (0..<10).flatMap { digit in
                [UInt8](repeating: UInt8(48 + digit), count: copiesPerDigit)
            }
            var remainderCandidates = (0..<10).map { UInt8(48 + $0) }
            shuffle(&remainderCandidates, using: &random)
            digits.append(contentsOf: remainderCandidates.prefix(count % 10))
            return digits
        }
    }

    private static func shuffle<Element>(
        _ values: inout [Element],
        using random: inout SplitMix64
    ) {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            values.swapAt(index, random.nextInt(upperBound: index + 1))
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
