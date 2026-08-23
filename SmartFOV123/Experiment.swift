import CoreText
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

enum DigitInputMethod: String, Decodable, Encodable, Sendable {
    case keyboard
    case speech
}

enum StopCommandInputMethod: String, Decodable, Encodable, Sendable {
    case keyboardSpace = "keyboard_space"
    case speechStop = "speech_stop"
}

struct InputConfiguration: Decodable, Encodable, Sendable {
    let startDigits: DigitInputMethod
    let stopCommand: StopCommandInputMethod
    let crossDigits: DigitInputMethod

    var usesTrialSpeech: Bool {
        startDigits == .speech || stopCommand == .speechStop || crossDigits == .speech
    }

    private enum CodingKeys: String, CodingKey {
        case startDigits = "start_digits"
        case stopCommand = "stop_command"
        case crossDigits = "cross_digits"
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
    let passthroughDimming: Double
}

struct SpeechConfiguration: Sendable {
    let digitAliases: [String: [String]]
    let maxInterdigitPauseSeconds: Float

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
    let digitHighlightCorrectRGB: RGB
    let digitHighlightWrongRGB: RGB
    let digitHighlightFontName: String

    let annotationHeightArcmin: Float
    let annotationFontName: String
    let annotationFontRGB: RGB

    let timeBarFillRGB: RGB
    let timeBarHeightArcmin: Float
    let timeBarCornerRadiusArcmin: Float
    let timeBarBackRGB: RGB
    let timeBarBackHeightArcmin: Float
    let timeBarBackCornerRadiusArcmin: Float
    let stopwatchVolume: Float
    let finalGongVolume: Float

    let correctFeedbackFile: String
    let correctFeedbackVolume: Float
    let wrongFeedbackFile: String
    let wrongFeedbackVolume: Float

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
    let fovZoomedWidthDegrees: Float
    let fovZoomedHeightDegrees: Float
    let fovHorizontalOffsetDegrees: Float
    let fovVerticalOffsetDegrees: Float
    let distanceMeters: Float

    var fovWidthScaleFactor: Float {
        Self.planarScaleFactor(from: fovWidthDegrees, to: fovZoomedWidthDegrees)
    }

    var fovHeightScaleFactor: Float {
        Self.planarScaleFactor(from: fovHeightDegrees, to: fovZoomedHeightDegrees)
    }

    private static func planarScaleFactor(from sourceDegrees: Float, to zoomedDegrees: Float) -> Float {
        // This treats the configured offsets as the stimulus center. An offset
        // changes the exact retinal visual angle at the edges, but intentionally
        // does not participate in the zoom calculation.
        tan(zoomedDegrees * .pi / 360) / tan(sourceDegrees * .pi / 360)
    }
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
    let conditionNumber: Int
    let blockNumber: Int
    let randomSeed: UInt64
    let configuration: ExperimentConfiguration
    let grid: NumberGrid
}

struct ScheduledTrial: Sendable {
    let trialNumber: Int
    let conditionNumber: Int
    let blockNumber: Int
    let configuration: ExperimentConfiguration

    func instantiate(trialNumber: Int? = nil) -> Experiment {
        let seed = configuration.stimulus.randomSeed
        return Experiment(
            trialNumber: trialNumber ?? self.trialNumber,
            conditionNumber: conditionNumber,
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
    let debriefingTitle: String
    let debriefing: String
    let taskMode: TaskMode
    let input: InputConfiguration
    /// Compositor-layer configuration is fixed for the duration of a session,
    /// so this option applies consistently to every trial in the plan.
    let foveatedRendering: Bool
    let trials: [ScheduledTrial]

    static func load(from url: URL, protocolName: String? = nil) throws -> ExperimentPlan {
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

        return try ConditionResolver.makePlan(
            from: file,
            protocolName: protocolName ?? url.deletingPathExtension().lastPathComponent
        )
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

struct ProtocolCatalog: Sendable {
    private static let managedExampleName = "example_do_not_edit"
    private static let legacyExampleName = "example"

    let plans: [ExperimentPlan]
    let foveatedRendering: Bool

    static func loadAvailable() throws -> ProtocolCatalog {
        let fileManager = FileManager.default
        let documentsURL: URL
        do {
            documentsURL = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw ExperimentError.protocolDirectoryUnavailable(error)
        }

        let protocolsURL = documentsURL.appendingPathComponent(
            "protocols",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: protocolsURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ExperimentError.protocolDirectoryUnavailable(error)
        }

        try removeLegacyExample(in: protocolsURL, using: fileManager)
        let userExampleURL = protocolsURL.appendingPathComponent(
            "\(managedExampleName).json",
            isDirectory: false
        )
        try installBundledExample(at: userExampleURL, using: fileManager)
        let availableProtocolURLs = try protocolURLs(in: protocolsURL, using: fileManager)

        let visibleProtocolURLs = availableProtocolURLs.filter {
            !$0.deletingPathExtension().lastPathComponent.hasPrefix("_")
        }
        let userProtocolURLs = visibleProtocolURLs.filter {
            $0.deletingPathExtension().lastPathComponent != managedExampleName
        }
        let candidates = userProtocolURLs.isEmpty
            ? visibleProtocolURLs.filter {
                $0.deletingPathExtension().lastPathComponent == managedExampleName
            }
            : userProtocolURLs
        var validPlans: [ExperimentPlan] = []
        var failures: [String] = []
        for url in candidates {
            let name = url.deletingPathExtension().lastPathComponent
            do {
                validPlans.append(try ExperimentPlan.load(from: url, protocolName: name))
            } catch {
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        validPlans.sort { $0.protocolName.localizedStandardCompare($1.protocolName) == .orderedAscending }
        guard !validPlans.isEmpty else {
            let detail = failures.isEmpty
                ? "No visible JSON protocol files were found in the Documents/protocols folder."
                : failures.joined(separator: "\n")
            throw ExperimentError.invalidConfiguration(detail)
        }
        let foveationValues = Set(validPlans.map(\.foveatedRendering))
        guard foveationValues.count == 1, let foveatedRendering = foveationValues.first else {
            throw ExperimentError.invalidConfiguration(
                "All visible protocols must use the same foveated_rendering value because compositor configuration is fixed before spoken protocol selection."
            )
        }
        return .init(plans: validPlans, foveatedRendering: foveatedRendering)
    }

    private static func protocolURLs(in directoryURL: URL, using fileManager: FileManager) throws -> [URL] {
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            )
        } catch {
            throw ExperimentError.protocolDirectoryUnavailable(error)
        }
        return urls.filter { url in
            url.pathExtension.caseInsensitiveCompare("json") == .orderedSame
                && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private static func removeLegacyExample(
        in protocolsURL: URL,
        using fileManager: FileManager
    ) throws {
        let legacyURL = protocolsURL.appendingPathComponent("\(legacyExampleName).json")
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }

        do {
            try fileManager.removeItem(at: legacyURL)
        } catch {
            throw ExperimentError.couldNotRestoreExample(error)
        }
    }

    private static func installBundledExample(
        at destinationURL: URL,
        using fileManager: FileManager
    ) throws {
        guard let sourceURL = bundledExampleURL() else {
            throw ExperimentError.missingConfiguration
        }

        let stagedURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            "_\(managedExampleName)_restore_\(UUID().uuidString).json"
        )
        defer {
            try? fileManager.removeItem(at: stagedURL)
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: stagedURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagedURL)
            } else {
                try fileManager.moveItem(at: stagedURL, to: destinationURL)
            }
        } catch {
            throw ExperimentError.couldNotRestoreExample(error)
        }
    }

    private static func bundledExampleURL() -> URL? {
        Bundle.main.url(forResource: managedExampleName, withExtension: "json")
            ?? Bundle.main.url(
                forResource: managedExampleName,
                withExtension: "json",
                subdirectory: "Protocols"
            )
    }
}

enum ExperimentError: LocalizedError {
    case missingConfiguration
    case protocolDirectoryUnavailable(Error)
    case couldNotRestoreExample(Error)
    case unreadableConfiguration(Error)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "The bundled example protocol is unavailable."
        case .protocolDirectoryUnavailable(let error):
            return "The Documents/protocols directory is unavailable: \(error.localizedDescription)"
        case .couldNotRestoreExample(let error):
            return "The bundled example protocol couldn't be restored to Documents/protocols: \(error.localizedDescription)"
        case .unreadableConfiguration(let error):
            return "The protocol file couldn't be read: \(error.localizedDescription)"
        case .invalidConfiguration(let message):
            return "The protocol configuration is invalid: \(message)"
        }
    }
}

private struct ExperimentFile: Decodable {
    let schemaVersion: Int
    let subjectNumberDigitCount: Int
    let instructions: String
    let debriefingTitle: String
    let debriefing: String
    let taskMode: TaskMode
    let input: InputConfiguration
    let foveatedRendering: Bool?
    let masterConditionTemplate: ConditionDefinition
    let conditions: [ConditionDefinition]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case subjectNumberDigitCount = "subject_number_digit_count"
        case instructions
        case debriefingTitle = "debriefing_title"
        case debriefing
        case taskMode = "task_mode"
        case input
        case foveatedRendering = "foveated_rendering"
        case masterConditionTemplate = "master_condition_template"
        case conditions
    }
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
    let highlightCorrectRGB: RGB?
    let highlightWrongRGB: RGB?
    let highlightFont: String?

    private enum CodingKeys: String, CodingKey {
        case heightDegrees = "height_degrees"
        case fontName = "font_name"
        case rgb
        case randomMethod = "random_method"
        case highlightCorrectRGB = "highlight_correct_rgb"
        case highlightWrongRGB = "highlight_wrong_rgb"
        case highlightFont = "highlight_font"
    }
}

private struct AnnotationPatch: Decodable {
    let heightDegrees: Float?
    let fontName: String?
    let fontRGB: RGB?

    private enum CodingKeys: String, CodingKey {
        case heightDegrees = "height_degrees"
        case fontName = "font_name"
        case fontRGB = "font_rgb"
    }
}

private struct CountdownBarPatch: Decodable {
    let fillRGB: RGB?
    let heightDegrees: Float?
    let cornerRadiusDegrees: Float?
    let backRGB: RGB?
    let backHeightDegrees: Float?
    let backCornerRadiusDegrees: Float?

    private enum CodingKeys: String, CodingKey {
        case fillRGB = "fill_rgb"
        case heightDegrees = "height_degrees"
        case cornerRadiusDegrees = "corner_radius_degrees"
        case backRGB = "back_rgb"
        case backHeightDegrees = "back_height_degrees"
        case backCornerRadiusDegrees = "back_corner_radius_degrees"
    }
}

private struct CountdownPatch: Decodable {
    let bar: CountdownBarPatch?
    let stopwatchVolume: Float?
    let finalGongVolume: Float?

    private enum CodingKeys: String, CodingKey {
        case bar
        case stopwatchVolume = "stopwatch_volume"
        case finalGongVolume = "final_gong_volume"
    }
}

private struct FeedbackSoundPatch: Decodable {
    let file: String?
    let volume: Float?
}

private struct FeedbackSoundsPatch: Decodable {
    let correct: FeedbackSoundPatch?
    let wrong: FeedbackSoundPatch?
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
    let zoomedWidthDegrees: Float?
    let zoomedHeightDegrees: Float?
    let horizontalOffsetDegrees: Float?
    let verticalOffsetDegrees: Float?
    let distanceMeters: Float?

    private enum CodingKeys: String, CodingKey {
        case eye, mode
        case peakOpacity = "peak_opacity"
        case widthDegrees = "width_degrees"
        case heightDegrees = "height_degrees"
        case zoomedWidthDegrees = "zoomed_width_degrees"
        case zoomedHeightDegrees = "zoomed_height_degrees"
        case horizontalOffsetDegrees = "horizontal_offset_degrees"
        case verticalOffsetDegrees = "vertical_offset_degrees"
        case distanceMeters = "distance_meters"
    }
}

private struct SpeechPatch: Decodable {
    let aliases: [String: [String]]?
    let maxInterdigitPauseSeconds: Float?

    private enum CodingKeys: String, CodingKey {
        case aliases
        case maxInterdigitPauseSeconds = "max_interdigit_pause_seconds"
    }
}

private struct ConditionDefinition: Decodable {
    let blockNumber: Int?
    let repeats: Int?
    let randomSeed: RandomSeedSpecification?
    let passthroughDimming: Double?
    let digits: DigitPatch?
    let annotation: AnnotationPatch?
    let countdown: CountdownPatch?
    let feedbackSounds: FeedbackSoundsPatch?
    let tiles: TilePatch?
    let surround: SurroundPatch?
    let fov: FOVPatch?
    let speech: SpeechPatch?

    private enum CodingKeys: String, CodingKey {
        case repeats
        case randomSeed = "random_seed"
        case passthroughDimming = "passthrough_dimming"
        case blockNumber = "block_nr"
        case digits, annotation, countdown, feedbackSounds = "feedback_sounds", tiles, surround, fov, speech
    }

}

private struct ResolvedConditionPatch {
    var blockNumber: Int?
    var repeats: Int?
    var randomSeed: RandomSeedSpecification?
    var passthroughDimming: Double?
    var digits = ResolvedDigits()
    var annotation = ResolvedAnnotation()
    var timeBar = ResolvedTimeBar()
    var countdownAudio = ResolvedCountdownAudio()
    var feedbackSounds = ResolvedFeedbackSounds()
    var tiles = ResolvedTiles()
    var surround = ResolvedSurround()
    var fov = ResolvedFOV()
    var aliases: [String: [String]] = [:]
    var speechMaxInterdigitPauseSeconds: Float?

    mutating func apply(_ definition: ConditionDefinition) {
        blockNumber = definition.blockNumber ?? blockNumber
        repeats = definition.repeats ?? repeats
        randomSeed = definition.randomSeed ?? randomSeed
        passthroughDimming = definition.passthroughDimming ?? passthroughDimming

        if let patch = definition.digits {
            digits.heightDegrees = patch.heightDegrees ?? digits.heightDegrees
            digits.fontName = patch.fontName ?? digits.fontName
            digits.rgb = patch.rgb ?? digits.rgb
            digits.randomMethod = patch.randomMethod ?? digits.randomMethod
            digits.highlightCorrectRGB = patch.highlightCorrectRGB ?? digits.highlightCorrectRGB
            digits.highlightWrongRGB = patch.highlightWrongRGB ?? digits.highlightWrongRGB
            digits.highlightFont = patch.highlightFont ?? digits.highlightFont
        }
        if let patch = definition.annotation {
            annotation.heightDegrees = patch.heightDegrees ?? annotation.heightDegrees
            annotation.fontName = patch.fontName ?? annotation.fontName
            annotation.fontRGB = patch.fontRGB ?? annotation.fontRGB
        }
        if let patch = definition.countdown?.bar {
            timeBar.fillRGB = patch.fillRGB ?? timeBar.fillRGB
            timeBar.heightDegrees = patch.heightDegrees ?? timeBar.heightDegrees
            timeBar.cornerRadiusDegrees = patch.cornerRadiusDegrees
                ?? timeBar.cornerRadiusDegrees
            timeBar.backRGB = patch.backRGB ?? timeBar.backRGB
            timeBar.backHeightDegrees = patch.backHeightDegrees ?? timeBar.backHeightDegrees
            timeBar.backCornerRadiusDegrees = patch.backCornerRadiusDegrees
                ?? timeBar.backCornerRadiusDegrees
        }
        countdownAudio.stopwatchVolume = definition.countdown?.stopwatchVolume
            ?? countdownAudio.stopwatchVolume
        countdownAudio.finalGongVolume = definition.countdown?.finalGongVolume
            ?? countdownAudio.finalGongVolume
        if let patch = definition.feedbackSounds?.correct {
            feedbackSounds.correctFile = patch.file ?? feedbackSounds.correctFile
            feedbackSounds.correctVolume = patch.volume ?? feedbackSounds.correctVolume
        }
        if let patch = definition.feedbackSounds?.wrong {
            feedbackSounds.wrongFile = patch.file ?? feedbackSounds.wrongFile
            feedbackSounds.wrongVolume = patch.volume ?? feedbackSounds.wrongVolume
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
            fov.zoomedWidthDegrees = patch.zoomedWidthDegrees ?? fov.zoomedWidthDegrees
            fov.zoomedHeightDegrees = patch.zoomedHeightDegrees ?? fov.zoomedHeightDegrees
            fov.horizontalOffsetDegrees = patch.horizontalOffsetDegrees ?? fov.horizontalOffsetDegrees
            fov.verticalOffsetDegrees = patch.verticalOffsetDegrees ?? fov.verticalOffsetDegrees
            fov.distanceMeters = patch.distanceMeters ?? fov.distanceMeters
        }
        if let patch = definition.speech?.aliases {
            aliases.merge(patch) { _, child in child }
        }
        speechMaxInterdigitPauseSeconds = definition.speech?.maxInterdigitPauseSeconds
            ?? speechMaxInterdigitPauseSeconds
    }
}

private struct ResolvedDigits {
    var heightDegrees: Float?
    var fontName: String?
    var rgb: RGB?
    var randomMethod: DigitRandomMethod?
    var highlightCorrectRGB: RGB?
    var highlightWrongRGB: RGB?
    var highlightFont: String?
}

private struct ResolvedAnnotation {
    var heightDegrees: Float?
    var fontName: String?
    var fontRGB: RGB?
}

private struct ResolvedTimeBar {
    var fillRGB: RGB?
    var heightDegrees: Float?
    var cornerRadiusDegrees: Float?
    var backRGB: RGB?
    var backHeightDegrees: Float?
    var backCornerRadiusDegrees: Float?
}

private struct ResolvedCountdownAudio {
    var stopwatchVolume: Float?
    var finalGongVolume: Float?
}

private struct ResolvedFeedbackSounds {
    var correctFile: String?
    var correctVolume: Float?
    var wrongFile: String?
    var wrongVolume: Float?
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
    var zoomedWidthDegrees: Float?
    var zoomedHeightDegrees: Float?
    var horizontalOffsetDegrees: Float?
    var verticalOffsetDegrees: Float?
    var distanceMeters: Float?
}

private struct ExpandedCondition {
    let number: Int
    let blockNumber: Int
    let seed: UInt64
    let patch: ResolvedConditionPatch
}

private enum ConditionResolver {
    static let maximumTrialCount = 10_000

    static func makePlan(from file: ExperimentFile, protocolName: String) throws -> ExperimentPlan {
        guard file.schemaVersion == 9 else {
            throw ExperimentError.invalidConfiguration(
                "schema_version \(file.schemaVersion) is unsupported; this app requires version 9."
            )
        }
        guard !file.conditions.isEmpty else {
            throw ExperimentError.invalidConfiguration("conditions must contain at least one condition.")
        }
        guard !protocolName.isEmpty, !protocolName.hasPrefix("_") else {
            throw ExperimentError.invalidConfiguration("The protocol filename is invalid.")
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
        let debriefingTitle = file.debriefingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !debriefingTitle.isEmpty, debriefingTitle == file.debriefingTitle else {
            throw ExperimentError.invalidConfiguration(
                "debriefing_title must be nonempty and have no leading or trailing whitespace."
            )
        }

        guard file.masterConditionTemplate.blockNumber == nil else {
            throw ExperimentError.invalidConfiguration(
                "master_condition_template must not define block_nr."
            )
        }
        guard file.masterConditionTemplate.repeats == nil else {
            throw ExperimentError.invalidConfiguration(
                "master_condition_template must not define repeats."
            )
        }
        var master = ResolvedConditionPatch()
        master.apply(file.masterConditionTemplate)
        try validateResolved(master, definitionName: "master_condition_template")
        guard master.randomSeed != nil else {
            throw ExperimentError.invalidConfiguration(
                "master_condition_template must define random_seed."
            )
        }

        var expanded: [ExpandedCondition] = []

        for (index, definition) in file.conditions.enumerated() {
            let conditionNumber = index + 1
            let definitionName = "condition \(conditionNumber)"
            guard let repeats = definition.repeats else {
                throw invalid(definitionName, "must explicitly define repeats.")
            }
            guard let blockNumber = definition.blockNumber else {
                throw invalid(definitionName, "must explicitly define block_nr.")
            }
            guard repeats > 0 else {
                throw invalid(definitionName, "repeats must be greater than zero.")
            }
            guard repeats <= maximumTrialCount else {
                throw invalid(definitionName, "repeats may not exceed \(maximumTrialCount).")
            }
            guard blockNumber > 0 else {
                throw invalid(definitionName, "block_nr must be at least 1.")
            }
            var patch = master
            patch.apply(definition)
            try validateResolved(patch, definitionName: definitionName)
            guard let seedSpecification = patch.randomSeed else {
                throw invalid(definitionName, "does not resolve random_seed; define it in master_condition_template or this condition.")
            }

            let seeds = try expandSeeds(
                seedSpecification,
                repeats: repeats,
                definitionName: definitionName
            )
            for seed in seeds {
                guard expanded.count < maximumTrialCount else {
                    throw ExperimentError.invalidConfiguration(
                        "The expanded experiment may contain at most \(maximumTrialCount) trials."
                    )
                }
                expanded.append(
                    .init(
                        number: conditionNumber,
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
        try validateBlocks(expanded.map(\.blockNumber))
        let ordered = randomizedWithinBlocks(expanded)
        let trials = try ordered.enumerated().map { offset, condition in
            let configuration = try makeConfiguration(from: condition)
            return ScheduledTrial(
                trialNumber: offset + 1,
                conditionNumber: condition.number,
                blockNumber: condition.blockNumber,
                configuration: configuration
            )
        }
        let gridSizes = Set(trials.map { trial in
            let stimulus = trial.configuration.stimulus
            return "\(stimulus.numberOfTilesHorizontal)x\(stimulus.numberOfTilesVertical)"
        })
        let gridSizeDescription = gridSizes.sorted().joined(separator: " or ")
        var resolvedInstructions = instructions
            .replacingOccurrences(
                of: "<NUMBEROFTRIALS>",
                with: String(trials.count)
            )
            .replacingOccurrences(
                of: "<GRIDSIZE>",
                with: gridSizeDescription
            )
        if let durationSeconds = file.taskMode.durationSeconds {
            resolvedInstructions = resolvedInstructions.replacingOccurrences(
                of: "<TIMER_SECONDS>",
                with: String(durationSeconds)
            )
        } else {
            resolvedInstructions = resolvedInstructions.replacingOccurrences(
                of: "<TIMER_SECONDS>",
                with: "unlimited"
            )
        }
        return ExperimentPlan(
            protocolName: protocolName,
            subjectNumberDigitCount: file.subjectNumberDigitCount,
            instructions: resolvedInstructions,
            debriefingTitle: debriefingTitle,
            debriefing: debriefing,
            taskMode: file.taskMode,
            input: file.input,
            foveatedRendering: file.foveatedRendering ?? true,
            trials: trials
        )
    }

    private static func validateResolved(
        _ patch: ResolvedConditionPatch,
        definitionName: String
    ) throws {
        func missing(_ name: String) throws -> Never {
            throw invalid(definitionName, "does not resolve parameter \(name); master_condition_template must define every stimulus parameter.")
        }
        guard let digitHeight = patch.digits.heightDegrees else { try missing("digits.height_degrees") }
        guard let fontName = patch.digits.fontName else { try missing("digits.font_name") }
        guard patch.digits.rgb != nil else { try missing("digits.rgb") }
        guard patch.digits.randomMethod != nil else { try missing("digits.random_method") }
        guard patch.digits.highlightCorrectRGB != nil else { try missing("digits.highlight_correct_rgb") }
        guard patch.digits.highlightWrongRGB != nil else { try missing("digits.highlight_wrong_rgb") }
        guard let highlightFont = patch.digits.highlightFont else {
            try missing("digits.highlight_font")
        }
        guard let annotationHeight = patch.annotation.heightDegrees else {
            try missing("annotation.height_degrees")
        }
        guard let annotationFontName = patch.annotation.fontName else {
            try missing("annotation.font_name")
        }
        guard patch.annotation.fontRGB != nil else { try missing("annotation.font_rgb") }
        guard patch.timeBar.fillRGB != nil else { try missing("countdown.bar.fill_rgb") }
        guard let timeBarHeight = patch.timeBar.heightDegrees else {
            try missing("countdown.bar.height_degrees")
        }
        guard let timeBarCornerRadius = patch.timeBar.cornerRadiusDegrees else {
            try missing("countdown.bar.corner_radius_degrees")
        }
        guard patch.timeBar.backRGB != nil else { try missing("countdown.bar.back_rgb") }
        guard let timeBarBackHeight = patch.timeBar.backHeightDegrees else {
            try missing("countdown.bar.back_height_degrees")
        }
        guard let stopwatchVolume = patch.countdownAudio.stopwatchVolume else {
            try missing("countdown.stopwatch_volume")
        }
        guard let finalGongVolume = patch.countdownAudio.finalGongVolume else {
            try missing("countdown.final_gong_volume")
        }
        guard let correctFeedbackFile = patch.feedbackSounds.correctFile else {
            try missing("feedback_sounds.correct.file")
        }
        guard let correctFeedbackVolume = patch.feedbackSounds.correctVolume else {
            try missing("feedback_sounds.correct.volume")
        }
        guard let wrongFeedbackFile = patch.feedbackSounds.wrongFile else {
            try missing("feedback_sounds.wrong.file")
        }
        guard let wrongFeedbackVolume = patch.feedbackSounds.wrongVolume else {
            try missing("feedback_sounds.wrong.volume")
        }
        guard let tileWidth = patch.tiles.widthDegrees else { try missing("tiles.width_degrees") }
        guard let tileHeight = patch.tiles.heightDegrees else { try missing("tiles.height_degrees") }
        guard let tileGutter = patch.tiles.gutterDegrees else { try missing("tiles.gutter_degrees") }
        guard let tileCornerRadius = patch.tiles.cornerRadiusDegrees else { try missing("tiles.corner_radius_degrees") }
        guard let timeBarBackCornerRadius = patch.timeBar.backCornerRadiusDegrees else {
            try missing("countdown.bar.back_corner_radius_degrees")
        }
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
        guard let passthroughDimming = patch.passthroughDimming else { try missing("passthrough_dimming") }
        guard let fovWidth = patch.fov.widthDegrees else { try missing("fov.width_degrees") }
        guard let fovHeight = patch.fov.heightDegrees else { try missing("fov.height_degrees") }
        guard let fovZoomedWidth = patch.fov.zoomedWidthDegrees else { try missing("fov.zoomed_width_degrees") }
        guard let fovZoomedHeight = patch.fov.zoomedHeightDegrees else { try missing("fov.zoomed_height_degrees") }
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
            ("countdown.bar.height_degrees", timeBarHeight),
            ("countdown.bar.back_height_degrees", timeBarBackHeight),
            ("tiles.width_degrees", tileWidth),
            ("tiles.height_degrees", tileHeight),
            ("fov.width_degrees", fovWidth),
            ("fov.height_degrees", fovHeight),
            ("fov.zoomed_width_degrees", fovZoomedWidth),
            ("fov.zoomed_height_degrees", fovZoomedHeight),
            ("fov.distance_meters", distance)
        ]
        for (name, value) in positive where !value.isFinite || value <= 0 {
            throw invalid(definitionName, "\(name) must be finite and greater than zero.")
        }
        for (name, value) in [
            ("fov.width_degrees", fovWidth),
            ("fov.height_degrees", fovHeight),
            ("fov.zoomed_width_degrees", fovZoomedWidth),
            ("fov.zoomed_height_degrees", fovZoomedHeight)
        ] where value >= 180 {
            throw invalid(definitionName, "\(name) must be less than 180 degrees.")
        }
        let nonnegative: [(String, Float)] = [
            ("tiles.gutter_degrees", tileGutter),
            ("tiles.corner_radius_degrees", tileCornerRadius),
            ("countdown.bar.corner_radius_degrees", timeBarCornerRadius),
            ("countdown.bar.back_corner_radius_degrees", timeBarBackCornerRadius),
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
        guard passthroughDimming.isFinite, (0...1).contains(passthroughDimming) else {
            throw invalid(definitionName, "passthrough_dimming must be between 0 and 1.")
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
        guard timeBarCornerRadius * 2 <= timeBarHeight else {
            throw invalid(definitionName, "countdown.bar.corner_radius_degrees is too large for height_degrees.")
        }
        guard timeBarBackCornerRadius * 2 <= timeBarBackHeight else {
            throw invalid(definitionName, "countdown.bar.back_corner_radius_degrees is too large for back_height_degrees.")
        }
        guard stopwatchVolume.isFinite, (0...1).contains(stopwatchVolume) else {
            throw invalid(
                definitionName,
                "countdown.stopwatch_volume must be finite and between zero and one."
            )
        }
        for (name, volume) in [
            ("countdown.final_gong_volume", finalGongVolume),
            ("feedback_sounds.correct.volume", correctFeedbackVolume),
            ("feedback_sounds.wrong.volume", wrongFeedbackVolume)
        ] where !volume.isFinite || !(0...1).contains(volume) {
            throw invalid(definitionName, "\(name) must be finite and between zero and one.")
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
        guard spaceAboveCenteredGrid >= timeBarBackHeight else {
            throw invalid(
                definitionName,
                "fov.height_degrees leaves insufficient space below the centered tile grid for countdown.bar.back_height_degrees."
            )
        }
        guard !fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid(definitionName, "digits.font_name must not be empty.")
        }
        guard fontIsAvailable(named: fontName) else {
            throw invalid(
                definitionName,
                "digits.font_name ‘\(fontName)’ is not installed on this device."
            )
        }
        guard !highlightFont.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid(definitionName, "digits.highlight_font must not be empty.")
        }
        guard fontIsAvailable(named: highlightFont) else {
            throw invalid(
                definitionName,
                "digits.highlight_font ‘\(highlightFont)’ is not installed on this device."
            )
        }
        for (name, file) in [
            ("feedback_sounds.correct.file", correctFeedbackFile),
            ("feedback_sounds.wrong.file", wrongFeedbackFile)
        ] {
            guard !file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  file == file.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw invalid(definitionName, "\(name) must be a nonempty filename without surrounding whitespace.")
            }
        }
        guard !annotationFontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid(definitionName, "annotation.font_name must not be empty.")
        }
        guard fontIsAvailable(named: annotationFontName) else {
            throw invalid(
                definitionName,
                "annotation.font_name ‘\(annotationFontName)’ is not installed on this device."
            )
        }
        guard let speechMaxInterdigitPauseSeconds = patch.speechMaxInterdigitPauseSeconds else {
            try missing("speech.max_interdigit_pause_seconds")
        }
        guard speechMaxInterdigitPauseSeconds.isFinite,
              speechMaxInterdigitPauseSeconds > 0 else {
            throw invalid(
                definitionName,
                "speech.max_interdigit_pause_seconds must be finite and greater than zero."
            )
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

    private static func fontIsAvailable(named name: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontNameAttribute: name] as CFDictionary
        )
        return CTFontDescriptorCreateMatchingFontDescriptor(
            descriptor,
            Set([kCTFontNameAttribute]) as CFSet
        ) != nil
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
                peakOpacity: patch.fov.peakOpacity!,
                passthroughDimming: patch.passthroughDimming!
            ),
            speech: .init(
                digitAliases: patch.aliases,
                maxInterdigitPauseSeconds: patch.speechMaxInterdigitPauseSeconds!
            ),
            stimulus: .init(
                eye: patch.fov.eye!,
                randomSeed: condition.seed,
                digitHeightArcmin: patch.digits.heightDegrees! * 60,
                digitFontName: patch.digits.fontName!,
                digitRGB: patch.digits.rgb!,
                digitRandomMethod: patch.digits.randomMethod!,
                digitHighlightCorrectRGB: patch.digits.highlightCorrectRGB!,
                digitHighlightWrongRGB: patch.digits.highlightWrongRGB!,
                digitHighlightFontName: patch.digits.highlightFont!,
                annotationHeightArcmin: patch.annotation.heightDegrees! * 60,
                annotationFontName: patch.annotation.fontName!,
                annotationFontRGB: patch.annotation.fontRGB!,
                timeBarFillRGB: patch.timeBar.fillRGB!,
                timeBarHeightArcmin: patch.timeBar.heightDegrees! * 60,
                timeBarCornerRadiusArcmin: patch.timeBar.cornerRadiusDegrees! * 60,
                timeBarBackRGB: patch.timeBar.backRGB!,
                timeBarBackHeightArcmin: patch.timeBar.backHeightDegrees! * 60,
                timeBarBackCornerRadiusArcmin: patch.timeBar.backCornerRadiusDegrees! * 60,
                stopwatchVolume: patch.countdownAudio.stopwatchVolume!,
                finalGongVolume: patch.countdownAudio.finalGongVolume!,
                correctFeedbackFile: patch.feedbackSounds.correctFile!,
                correctFeedbackVolume: patch.feedbackSounds.correctVolume!,
                wrongFeedbackFile: patch.feedbackSounds.wrongFile!,
                wrongFeedbackVolume: patch.feedbackSounds.wrongVolume!,
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
                fovZoomedWidthDegrees: patch.fov.zoomedWidthDegrees!,
                fovZoomedHeightDegrees: patch.fov.zoomedHeightDegrees!,
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
                "schema_version", "subject_number_digit_count",
                "instructions", "debriefing_title", "debriefing", "foveated_rendering", "task_mode",
                "input", "master_condition_template", "conditions"
            ],
            path: "$"
        )
        guard let rawInput = root["input"] else {
            throw invalid("$.input", "is required.")
        }
        try section(
            rawInput,
            path: "$.input",
            allowed: ["start_digits", "stop_command", "cross_digits"]
        )
        guard let rawMaster = root["master_condition_template"] else {
            throw invalid("$.master_condition_template", "is required.")
        }
        try definition(rawMaster, path: "$.master_condition_template", schedulingFields: false)
        guard let rawConditions = root["conditions"] as? [Any] else {
            throw invalid("$.conditions", "must be an array.")
        }
        for (index, rawCondition) in rawConditions.enumerated() {
            let path = "$.conditions[\(index)]"
            try definition(rawCondition, path: path, schedulingFields: true)
        }
    }

    private static func definition(
        _ rawDefinition: Any,
        path: String,
        schedulingFields: Bool
    ) throws {
            let condition = try dictionary(rawDefinition, path: path)
            var allowed: Set<String> = [
                "random_seed", "passthrough_dimming", "digits", "annotation", "countdown", "feedback_sounds", "tiles", "surround", "fov", "speech"
            ]
            if schedulingFields {
                allowed.formUnion(["block_nr", "repeats"])
            }
            try keys(condition, allowed: allowed, path: path)
            try section(
                condition["digits"],
                path: "\(path).digits",
                allowed: ["height_degrees", "font_name", "rgb", "random_method", "highlight_correct_rgb", "highlight_wrong_rgb", "highlight_font"]
            )
            try section(
                condition["annotation"],
                path: "\(path).annotation",
                allowed: ["height_degrees", "font_name", "font_rgb"]
            )
            try section(condition["countdown"], path: "\(path).countdown", allowed: ["bar", "stopwatch_volume", "final_gong_volume"])
            if let rawCountdown = condition["countdown"] {
                let countdown = try dictionary(rawCountdown, path: "\(path).countdown")
                try section(
                    countdown["bar"],
                    path: "\(path).countdown.bar",
                    allowed: ["fill_rgb", "height_degrees", "corner_radius_degrees", "back_rgb", "back_height_degrees", "back_corner_radius_degrees"]
                )
            }
            try section(condition["feedback_sounds"], path: "\(path).feedback_sounds", allowed: ["correct", "wrong"])
            if let rawFeedback = condition["feedback_sounds"] {
                let feedback = try dictionary(rawFeedback, path: "\(path).feedback_sounds")
                try section(feedback["correct"], path: "\(path).feedback_sounds.correct", allowed: ["file", "volume"])
                try section(feedback["wrong"], path: "\(path).feedback_sounds.wrong", allowed: ["file", "volume"])
            }
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
                allowed: ["eye", "mode", "peak_opacity", "width_degrees", "height_degrees", "zoomed_width_degrees", "zoomed_height_degrees", "horizontal_offset_degrees", "vertical_offset_degrees", "distance_meters"]
            )
            if let rawSpeech = condition["speech"] {
                let speech = try dictionary(rawSpeech, path: "\(path).speech")
                try keys(
                    speech,
                    allowed: ["aliases", "max_interdigit_pause_seconds"],
                    path: "\(path).speech"
                )
                if let rawAliases = speech["aliases"] {
                    let aliases = try dictionary(rawAliases, path: "\(path).speech.aliases")
                    try keys(aliases, allowed: Set((0...9).map(String.init)), path: "\(path).speech.aliases")
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
