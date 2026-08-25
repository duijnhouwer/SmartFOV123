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
    let speech: SpeechConfiguration

    var usesTrialSpeech: Bool {
        startDigits == .speech || stopCommand == .speechStop || crossDigits == .speech
    }

    var usesKeyboard: Bool {
        startDigits == .keyboard || stopCommand == .keyboardSpace || crossDigits == .keyboard
    }

    func replacingModesWithVoiceOnly() -> InputConfiguration {
        InputConfiguration(
            startDigits: .speech,
            stopCommand: .speechStop,
            crossDigits: .speech,
            speech: speech
        )
    }

    private enum CodingKeys: String, CodingKey {
        case startDigits = "start_digits"
        case stopCommand = "stop_command"
        case crossDigits = "cross_digits"
        case speech
    }
}

struct SoundEffectConfiguration: Decodable, Encodable, Sendable {
    let file: String
    let volume: Float
}

struct SoundsConfiguration: Decodable, Encodable, Sendable {
    let reveal: SoundEffectConfiguration
    let stopTimer: SoundEffectConfiguration
    let correct: SoundEffectConfiguration
    let wrong: SoundEffectConfiguration
    let timer: SoundEffectConfiguration
    let final: SoundEffectConfiguration

    private enum CodingKeys: String, CodingKey {
        case reveal
        case stopTimer = "stop_timer"
        case correct, wrong, timer, final
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

struct SpeechConfiguration: Decodable, Encodable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case digitAliases = "aliases"
        case maxInterdigitPauseSeconds = "max_interdigit_pause_seconds"
    }

}

struct StimulusConfiguration: Sendable {
    let eye: StimulusEye
    var randomSeed: UInt64

    let digitHeightArcmin: Float
    let digitFontName: String
    let digitRGB: RGB
    let digitRandomMethod: DigitRandomMethod
    let digitHighlightCorrectRGB: RGB?
    let digitHighlightWrongRGB: RGB?
    let postStopVisibilitySeconds: Float
    let maskingCharacter: String

    let annotationHeightArcmin: Float
    let annotationFontName: String
    let annotationFontRGB: RGB

    let timeBarFillRGB: RGB
    let timeBarHeightArcmin: Float
    let timeBarCornerRadiusArcmin: Float
    let timeBarBackRGB: RGB
    let timeBarBackHeightArcmin: Float
    let timeBarBackCornerRadiusArcmin: Float

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
    let fovZoomedWidthDegrees: Float?
    let fovZoomedHeightDegrees: Float?
    let fovHorizontalOffsetDegrees: Float
    let fovVerticalOffsetDegrees: Float
    let distanceMeters: Float

    var effectiveFOVZoomedWidthDegrees: Float {
        fovZoomedWidthDegrees ?? fovWidthDegrees
    }

    var effectiveFOVZoomedHeightDegrees: Float {
        fovZoomedHeightDegrees ?? fovHeightDegrees
    }

    var fovWidthScaleFactor: Float {
        Self.planarScaleFactor(from: fovWidthDegrees, to: effectiveFOVZoomedWidthDegrees)
    }

    var fovHeightScaleFactor: Float {
        Self.planarScaleFactor(from: fovHeightDegrees, to: effectiveFOVZoomedHeightDegrees)
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
    var stimulus: StimulusConfiguration
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
    let reshufflesSeedOnPresentation: Bool

    func instantiate(trialNumber: Int? = nil) -> Experiment {
        let seed: UInt64
        if reshufflesSeedOnPresentation {
            seed = UInt64.random(in: .min ... .max)
        } else {
            seed = configuration.stimulus.randomSeed
        }
        var instantiatedConfiguration = configuration
        instantiatedConfiguration.stimulus.randomSeed = seed
        return Experiment(
            trialNumber: trialNumber ?? self.trialNumber,
            conditionNumber: conditionNumber,
            blockNumber: blockNumber,
            randomSeed: seed,
            configuration: instantiatedConfiguration,
            grid: NumberGridGenerator.makeGrid(
                using: instantiatedConfiguration.stimulus,
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
    let sounds: SoundsConfiguration
    let input: InputConfiguration
    let trials: [ScheduledTrial]

    func replacingInput(with input: InputConfiguration) -> ExperimentPlan {
        ExperimentPlan(
            protocolName: protocolName,
            subjectNumberDigitCount: subjectNumberDigitCount,
            instructions: instructions,
            debriefingTitle: debriefingTitle,
            debriefing: debriefing,
            taskMode: taskMode,
            sounds: sounds,
            input: input,
            trials: trials
        )
    }

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

        let expandedData = try ConditionFactorExpander.expandConditions(in: data)
        let file: ExperimentFile
        do {
            file = try JSONDecoder().decode(ExperimentFile.self, from: expandedData)
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

private struct AppConfiguration: Sendable {
    private struct File: Decodable {
        let appSettings: AppSettings

        private enum CodingKeys: String, CodingKey {
            case appSettings = "app_settings"
        }
    }

    private struct AppSettings: Decodable {
        let foveatedRendering: Bool

        private enum CodingKeys: String, CodingKey {
            case foveatedRendering = "foveated_rendering"
        }
    }

    let foveatedRendering: Bool

    static func load(from documentsURL: URL, using fileManager: FileManager) throws -> AppConfiguration {
        let destinationURL = documentsURL.appendingPathComponent("config.json", isDirectory: false)
        if !fileManager.fileExists(atPath: destinationURL.path) {
            guard let sourceURL = Bundle.main.url(forResource: "config", withExtension: "json") else {
                throw ExperimentError.missingAppConfiguration
            }
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                throw ExperimentError.couldNotInstallAppConfiguration(error)
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: destinationURL)
        } catch {
            throw ExperimentError.unreadableAppConfiguration(error)
        }

        let rawObject: Any
        do {
            rawObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ExperimentError.invalidAppConfiguration(
                "config.json contains malformed JSON: \(error.localizedDescription)"
            )
        }
        guard let root = rawObject as? [String: Any] else {
            throw ExperimentError.invalidAppConfiguration("config.json root must be an object.")
        }
        try validateKeys(root, allowed: ["app_settings"], path: "config.json")
        guard let rawSettings = root["app_settings"] as? [String: Any] else {
            throw ExperimentError.invalidAppConfiguration("config.json.app_settings must be an object.")
        }
        try validateKeys(
            rawSettings,
            allowed: ["foveated_rendering"],
            path: "config.json.app_settings"
        )

        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw ExperimentError.invalidAppConfiguration(
                "config.json could not be decoded: \(error.localizedDescription)"
            )
        }
        return .init(foveatedRendering: file.appSettings.foveatedRendering)
    }

    private static func validateKeys(
        _ object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        let unknown = Set(object.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw ExperimentError.invalidAppConfiguration(
                "\(path) contains unknown key(s): \(unknown.joined(separator: ", "))."
            )
        }
    }
}

struct ProtocolCatalog: Sendable {
    struct InvalidProtocol: Sendable {
        let filename: String
        let errorMessage: String
    }

    private static let managedFallbackName = "fallback_do_not_edit"

    let plans: [ExperimentPlan]
    let invalidProtocols: [InvalidProtocol]
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

        let appConfiguration = try AppConfiguration.load(
            from: documentsURL,
            using: fileManager
        )

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

        let userFallbackURL = protocolsURL.appendingPathComponent(
            "\(managedFallbackName).json",
            isDirectory: false
        )
        try installBundledFallback(at: userFallbackURL, using: fileManager)
        let availableProtocolURLs = try protocolURLs(in: protocolsURL, using: fileManager)

        let visibleProtocolURLs = availableProtocolURLs.filter {
            !$0.deletingPathExtension().lastPathComponent.hasPrefix("_")
        }
        let userProtocolURLs = visibleProtocolURLs.filter {
            $0.deletingPathExtension().lastPathComponent != managedFallbackName
        }
        let fallbackURLs = visibleProtocolURLs.filter {
            $0.deletingPathExtension().lastPathComponent == managedFallbackName
        }

        func load(_ urls: [URL]) -> (plans: [ExperimentPlan], invalid: [InvalidProtocol]) {
            var plans: [ExperimentPlan] = []
            var invalid: [InvalidProtocol] = []
            for url in urls {
                let name = url.deletingPathExtension().lastPathComponent
                do {
                    plans.append(try ExperimentPlan.load(from: url, protocolName: name))
                } catch {
                    invalid.append(
                        .init(
                            filename: url.lastPathComponent,
                            errorMessage: error.localizedDescription
                        )
                    )
                }
            }
            plans.sort {
                $0.protocolName.localizedStandardCompare($1.protocolName) == .orderedAscending
            }
            invalid.sort {
                $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
            }
            return (plans, invalid)
        }

        let userCatalog = load(userProtocolURLs)
        let selectedCatalog: (plans: [ExperimentPlan], invalid: [InvalidProtocol])
        if userCatalog.plans.isEmpty {
            let fallbackCatalog = load(fallbackURLs)
            selectedCatalog = (
                plans: fallbackCatalog.plans,
                invalid: (userCatalog.invalid + fallbackCatalog.invalid).sorted {
                    $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
                }
            )
        } else {
            selectedCatalog = userCatalog
        }
        let validPlans = selectedCatalog.plans
        let invalidProtocols = selectedCatalog.invalid

        guard !validPlans.isEmpty || !invalidProtocols.isEmpty else {
            throw ExperimentError.invalidConfiguration(
                "No visible JSON protocol files were found in the Documents/protocols folder."
            )
        }
        return .init(
            plans: validPlans,
            invalidProtocols: invalidProtocols,
            foveatedRendering: appConfiguration.foveatedRendering
        )
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

    private static func installBundledFallback(
        at destinationURL: URL,
        using fileManager: FileManager
    ) throws {
        guard let sourceURL = bundledFallbackURL() else {
            throw ExperimentError.missingConfiguration
        }

        let stagedURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            "_\(managedFallbackName)_restore_\(UUID().uuidString).json"
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
            throw ExperimentError.couldNotRestoreFallback(error)
        }
    }

    private static func bundledFallbackURL() -> URL? {
        Bundle.main.url(forResource: managedFallbackName, withExtension: "json")
            ?? Bundle.main.url(
                forResource: managedFallbackName,
                withExtension: "json",
                subdirectory: "Protocols"
            )
    }
}

enum ExperimentError: LocalizedError {
    case missingConfiguration
    case missingAppConfiguration
    case protocolDirectoryUnavailable(Error)
    case couldNotRestoreFallback(Error)
    case couldNotInstallAppConfiguration(Error)
    case unreadableConfiguration(Error)
    case unreadableAppConfiguration(Error)
    case invalidAppConfiguration(String)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "The bundled fallback protocol is unavailable."
        case .missingAppConfiguration:
            return "The bundled config.json file is unavailable."
        case .protocolDirectoryUnavailable(let error):
            return "The Documents/protocols directory is unavailable: \(error.localizedDescription)"
        case .couldNotRestoreFallback(let error):
            return "The bundled fallback protocol couldn't be restored to Documents/protocols: \(error.localizedDescription)"
        case .couldNotInstallAppConfiguration(let error):
            return "config.json couldn't be installed in Documents: \(error.localizedDescription)"
        case .unreadableConfiguration(let error):
            return "The protocol file couldn't be read: \(error.localizedDescription)"
        case .unreadableAppConfiguration(let error):
            return "Documents/config.json couldn't be read: \(error.localizedDescription)"
        case .invalidAppConfiguration(let message):
            return "The app configuration is invalid: \(message)"
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
    let sounds: SoundsConfiguration
    let input: InputConfiguration
    let masterConditionTemplate: ConditionDefinition
    let conditions: [ConditionDefinition]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case subjectNumberDigitCount = "subject_number_digit_count"
        case instructions
        case debriefingTitle = "debriefing_title"
        case debriefing
        case taskMode = "task_mode"
        case sounds
        case input
        case masterConditionTemplate = "master_condition_template"
        case conditions
    }
}

private enum RandomSeedSpecification: Equatable {
    case shuffle
    case fixed(UInt64)
}

private enum HighlightSpecification: Decodable {
    case color(RGB)
    case disabled

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let keyword = try? container.decode(String.self) {
            guard keyword == "disabled" else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an RGB array or the string ‘disabled’."
                )
            }
            self = .disabled
        } else {
            self = .color(try container.decode(RGB.self))
        }
    }
}

private enum ZoomSpecification: Decodable {
    case degrees(Float)
    case disabled

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let keyword = try? container.decode(String.self) {
            guard keyword == "disabled" else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected a number or the string ‘disabled’."
                )
            }
            self = .disabled
        } else {
            self = .degrees(try container.decode(Float.self))
        }
    }
}

extension RandomSeedSpecification: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(UInt64.self) {
            self = .fixed(value)
        } else {
            let keyword = try container.decode(String.self)
            guard keyword == "shuffle" else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an unsigned integer or the string ‘shuffle’."
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
    let highlightCorrectRGB: HighlightSpecification?
    let highlightWrongRGB: HighlightSpecification?
    let postStopVisibilitySeconds: Float?
    let maskingCharacter: String?

    private enum CodingKeys: String, CodingKey {
        case heightDegrees = "height_degrees"
        case fontName = "font_name"
        case rgb
        case randomMethod = "random_method"
        case highlightCorrectRGB = "highlight_correct_rgb"
        case highlightWrongRGB = "highlight_wrong_rgb"
        case postStopVisibilitySeconds = "post_stop_visibility_seconds"
        case maskingCharacter = "masking_character"
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
    let zoomedWidthDegrees: ZoomSpecification?
    let zoomedHeightDegrees: ZoomSpecification?
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

private struct SchedulingDefinition: Decodable {
    let repeats: Int?
    let blockNumber: Int?

    private enum CodingKeys: String, CodingKey {
        case repeats
        case blockNumber = "block_nr"
    }
}

private struct ConditionDefinition: Decodable {
    let scheduling: SchedulingDefinition?
    let randomSeed: RandomSeedSpecification?
    let passthroughDimming: Double?
    let digits: DigitPatch?
    let annotation: AnnotationPatch?
    let timerBar: CountdownBarPatch?
    let tiles: TilePatch?
    let surround: SurroundPatch?
    let fov: FOVPatch?

    private enum CodingKeys: String, CodingKey {
        case scheduling
        case randomSeed = "random_seed"
        case passthroughDimming = "passthrough_dimming"
        case digits, annotation, timerBar = "timer_bar", tiles, surround, fov
    }

}

private struct ResolvedConditionPatch {
    var randomSeed: RandomSeedSpecification?
    var passthroughDimming: Double?
    var digits = ResolvedDigits()
    var annotation = ResolvedAnnotation()
    var timeBar = ResolvedTimeBar()
    var tiles = ResolvedTiles()
    var surround = ResolvedSurround()
    var fov = ResolvedFOV()

    mutating func apply(_ definition: ConditionDefinition) {
        randomSeed = definition.randomSeed ?? randomSeed
        passthroughDimming = definition.passthroughDimming ?? passthroughDimming

        if let patch = definition.digits {
            digits.heightDegrees = patch.heightDegrees ?? digits.heightDegrees
            digits.fontName = patch.fontName ?? digits.fontName
            digits.rgb = patch.rgb ?? digits.rgb
            digits.randomMethod = patch.randomMethod ?? digits.randomMethod
            digits.highlightCorrectRGB = patch.highlightCorrectRGB ?? digits.highlightCorrectRGB
            digits.highlightWrongRGB = patch.highlightWrongRGB ?? digits.highlightWrongRGB
            digits.postStopVisibilitySeconds = patch.postStopVisibilitySeconds
                ?? digits.postStopVisibilitySeconds
            digits.maskingCharacter = patch.maskingCharacter ?? digits.maskingCharacter
        }
        if let patch = definition.annotation {
            annotation.heightDegrees = patch.heightDegrees ?? annotation.heightDegrees
            annotation.fontName = patch.fontName ?? annotation.fontName
            annotation.fontRGB = patch.fontRGB ?? annotation.fontRGB
        }
        if let patch = definition.timerBar {
            timeBar.fillRGB = patch.fillRGB ?? timeBar.fillRGB
            timeBar.heightDegrees = patch.heightDegrees ?? timeBar.heightDegrees
            timeBar.cornerRadiusDegrees = patch.cornerRadiusDegrees ?? timeBar.cornerRadiusDegrees
            timeBar.backRGB = patch.backRGB ?? timeBar.backRGB
            timeBar.backHeightDegrees = patch.backHeightDegrees ?? timeBar.backHeightDegrees
            timeBar.backCornerRadiusDegrees = patch.backCornerRadiusDegrees ?? timeBar.backCornerRadiusDegrees
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
    }
}

private struct ResolvedDigits {
    var heightDegrees: Float?
    var fontName: String?
    var rgb: RGB?
    var randomMethod: DigitRandomMethod?
    var highlightCorrectRGB: HighlightSpecification?
    var highlightWrongRGB: HighlightSpecification?
    var postStopVisibilitySeconds: Float?
    var maskingCharacter: String?
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
    var zoomedWidthDegrees: ZoomSpecification?
    var zoomedHeightDegrees: ZoomSpecification?
    var horizontalOffsetDegrees: Float?
    var verticalOffsetDegrees: Float?
    var distanceMeters: Float?
}

private struct ExpandedCondition {
    let number: Int
    let blockNumber: Int
    let seed: UInt64
    let reshufflesSeedOnPresentation: Bool
    let patch: ResolvedConditionPatch
}

private enum ConditionResolver {
    static let maximumTrialCount = 10_000

    static func makePlan(from file: ExperimentFile, protocolName: String) throws -> ExperimentPlan {
        guard file.schemaVersion == 10 else {
            throw ExperimentError.invalidConfiguration(
                "schema_version \(file.schemaVersion) is unsupported; this app requires version 10."
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
        try validateSounds(file.sounds)
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

        try validateSpeech(file.input.speech)

        guard file.masterConditionTemplate.scheduling == nil else {
            throw ExperimentError.invalidConfiguration(
                "master_condition_template must not define scheduling."
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
            guard let scheduling = definition.scheduling else {
                throw invalid(definitionName, "must explicitly define scheduling.")
            }
            guard let repeats = scheduling.repeats else {
                throw invalid(definitionName, "scheduling must explicitly define repeats.")
            }
            guard let blockNumber = scheduling.blockNumber else {
                throw invalid(definitionName, "scheduling must explicitly define block_nr.")
            }
            guard repeats >= 0 else {
                throw invalid(definitionName, "repeats must be zero or greater.")
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

            let seeds = expandSeeds(seedSpecification, repeats: repeats)
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
                        reshufflesSeedOnPresentation: seedSpecification == .shuffle,
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
                configuration: configuration,
                reshufflesSeedOnPresentation: condition.reshufflesSeedOnPresentation
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
            sounds: file.sounds,
            input: file.input,
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
        guard let postStopVisibilitySeconds = patch.digits.postStopVisibilitySeconds else {
            try missing("digits.post_stop_visibility_seconds")
        }
        guard postStopVisibilitySeconds.isFinite, postStopVisibilitySeconds >= 0 else {
            throw invalid(definitionName, "digits.post_stop_visibility_seconds must be finite and at least zero.")
        }
        guard let maskingCharacter = patch.digits.maskingCharacter,
              maskingCharacter.count == 1,
              !maskingCharacter.unicodeScalars.contains(where: CharacterSet.newlines.contains) else {
            throw invalid(definitionName, "digits.masking_character must be exactly one non-newline character.")
        }
        guard let annotationHeight = patch.annotation.heightDegrees else {
            try missing("annotation.height_degrees")
        }
        guard let annotationFontName = patch.annotation.fontName else {
            try missing("annotation.font_name")
        }
        guard patch.annotation.fontRGB != nil else { try missing("annotation.font_rgb") }
        guard patch.timeBar.fillRGB != nil else { try missing("timer_bar.fill_rgb") }
        guard let timeBarHeight = patch.timeBar.heightDegrees else {
            try missing("timer_bar.height_degrees")
        }
        guard let timeBarCornerRadius = patch.timeBar.cornerRadiusDegrees else {
            try missing("timer_bar.corner_radius_degrees")
        }
        guard patch.timeBar.backRGB != nil else { try missing("timer_bar.back_rgb") }
        guard let timeBarBackHeight = patch.timeBar.backHeightDegrees else {
            try missing("timer_bar.back_height_degrees")
        }
        guard let tileWidth = patch.tiles.widthDegrees else { try missing("tiles.width_degrees") }
        guard let tileHeight = patch.tiles.heightDegrees else { try missing("tiles.height_degrees") }
        guard let tileGutter = patch.tiles.gutterDegrees else { try missing("tiles.gutter_degrees") }
        guard let tileCornerRadius = patch.tiles.cornerRadiusDegrees else { try missing("tiles.corner_radius_degrees") }
        guard let timeBarBackCornerRadius = patch.timeBar.backCornerRadiusDegrees else {
            try missing("timer_bar.back_corner_radius_degrees")
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
        guard let fovZoomedWidthSpecification = patch.fov.zoomedWidthDegrees else {
            try missing("fov.zoomed_width_degrees")
        }
        guard let fovZoomedHeightSpecification = patch.fov.zoomedHeightDegrees else {
            try missing("fov.zoomed_height_degrees")
        }
        let fovZoomedWidth: Float
        switch fovZoomedWidthSpecification {
        case .degrees(let degrees): fovZoomedWidth = degrees
        case .disabled: fovZoomedWidth = fovWidth
        }
        let fovZoomedHeight: Float
        switch fovZoomedHeightSpecification {
        case .degrees(let degrees): fovZoomedHeight = degrees
        case .disabled: fovZoomedHeight = fovHeight
        }
        guard let horizontalOffset = patch.fov.horizontalOffsetDegrees else { try missing("fov.horizontal_offset_degrees") }
        guard let verticalOffset = patch.fov.verticalOffsetDegrees else { try missing("fov.vertical_offset_degrees") }
        guard let distance = patch.fov.distanceMeters else { try missing("fov.distance_meters") }

        let positive: [(String, Float)] = [
            ("digits.height_degrees", digitHeight),
            ("annotation.height_degrees", annotationHeight),
            ("timer_bar.height_degrees", timeBarHeight),
            ("timer_bar.back_height_degrees", timeBarBackHeight),
            ("tiles.width_degrees", tileWidth),
            ("tiles.height_degrees", tileHeight),
            ("fov.width_degrees", fovWidth),
            ("fov.height_degrees", fovHeight),
            ("fov.distance_meters", distance)
        ]
        for (name, value) in positive where !value.isFinite || value <= 0 {
            throw invalid(definitionName, "\(name) must be finite and greater than zero.")
        }
        for (name, value) in [
            ("fov.width_degrees", fovWidth),
            ("fov.height_degrees", fovHeight)
        ] where value >= 180 {
            throw invalid(definitionName, "\(name) must be less than 180 degrees.")
        }
        for (name, value) in [
            ("fov.zoomed_width_degrees", fovZoomedWidth),
            ("fov.zoomed_height_degrees", fovZoomedHeight)
        ] where !value.isFinite || value == 0 || abs(value) >= 180 {
            throw invalid(
                definitionName,
                "\(name) must be ‘disabled’ or a nonzero finite value between -180 and 180 degrees."
            )
        }
        let nonnegative: [(String, Float)] = [
            ("tiles.gutter_degrees", tileGutter),
            ("tiles.corner_radius_degrees", tileCornerRadius),
            ("timer_bar.corner_radius_degrees", timeBarCornerRadius),
            ("timer_bar.back_corner_radius_degrees", timeBarBackCornerRadius),
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
            throw invalid(definitionName, "timer_bar.corner_radius_degrees is too large for height_degrees.")
        }
        guard timeBarBackCornerRadius * 2 <= timeBarBackHeight else {
            throw invalid(definitionName, "timer_bar.back_corner_radius_degrees is too large for back_height_degrees.")
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
                "fov.height_degrees leaves insufficient space below the centered tile grid for timer_bar.back_height_degrees."
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
        guard !annotationFontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid(definitionName, "annotation.font_name must not be empty.")
        }
        guard fontIsAvailable(named: annotationFontName) else {
            throw invalid(
                definitionName,
                "annotation.font_name ‘\(annotationFontName)’ is not installed on this device."
            )
        }
    }

    private static func validateSounds(_ sounds: SoundsConfiguration) throws {
        for (name, sound) in [
            ("sounds.reveal", sounds.reveal),
            ("sounds.stop_timer", sounds.stopTimer),
            ("sounds.correct", sounds.correct), ("sounds.wrong", sounds.wrong),
            ("sounds.timer", sounds.timer), ("sounds.final", sounds.final)
        ] {
            guard !sound.file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  sound.file == sound.file.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw ExperimentError.invalidConfiguration("\(name).file must be a nonempty filename without surrounding whitespace.")
            }
            guard sound.volume.isFinite, (0...1).contains(sound.volume) else {
                throw ExperimentError.invalidConfiguration("\(name).volume must be finite and between zero and one.")
            }
        }
    }


    private static func validateSpeech(_ speech: SpeechConfiguration) throws {
        let requiredDigitKeys = Set((0...9).map(String.init))
        guard Set(speech.digitAliases.keys) == requiredDigitKeys else {
            throw ExperimentError.invalidConfiguration("input.speech.aliases must define exactly the keys 0 through 9.")
        }
        var aliasOwners: [String: String] = [:]
        for digit in requiredDigitKeys.sorted() {
            guard let aliases = speech.digitAliases[digit], !aliases.isEmpty else {
                throw ExperimentError.invalidConfiguration("input.speech.aliases.\(digit) must contain at least one spoken form.")
            }
            var aliasesForDigit = Set<String>()
            for alias in aliases {
                let normalized = SpeechConfiguration.normalize(alias)
                guard !normalized.isEmpty,
                      normalized.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else {
                    throw ExperimentError.invalidConfiguration("input.speech.aliases.\(digit) contains ‘\(alias)’; aliases must be single words containing letters only.")
                }
                guard aliasesForDigit.insert(normalized).inserted else {
                    throw ExperimentError.invalidConfiguration("input.speech.aliases.\(digit) contains duplicate alias ‘\(normalized)’.")
                }
                if let existing = aliasOwners[normalized], existing != digit {
                    throw ExperimentError.invalidConfiguration("input.speech alias ‘\(normalized)’ belongs to both \(existing) and \(digit).")
                }
                aliasOwners[normalized] = digit
            }
        }
        guard speech.maxInterdigitPauseSeconds.isFinite,
              speech.maxInterdigitPauseSeconds > 0 else {
            throw ExperimentError.invalidConfiguration("input.speech.max_interdigit_pause_seconds must be finite and greater than zero.")
        }
    }

    private static func expandSeeds(
        _ specification: RandomSeedSpecification,
        repeats: Int
    ) -> [UInt64] {
        switch specification {
        case .shuffle:
            var generator = SystemRandomNumberGenerator()
            return (0..<repeats).map { _ in UInt64.random(in: .min ... .max, using: &generator) }
        case .fixed(let seed):
            return [UInt64](repeating: seed, count: repeats)
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
        var generator = SystemRandomNumberGenerator()
        return Set(conditions.map(\.blockNumber)).sorted().flatMap { block in
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
            stimulus: .init(
                eye: patch.fov.eye!,
                randomSeed: condition.seed,
                digitHeightArcmin: patch.digits.heightDegrees! * 60,
                digitFontName: patch.digits.fontName!,
                digitRGB: patch.digits.rgb!,
                digitRandomMethod: patch.digits.randomMethod!,
                digitHighlightCorrectRGB: {
                    switch patch.digits.highlightCorrectRGB! {
                    case .color(let color): color
                    case .disabled: nil
                    }
                }(),
                digitHighlightWrongRGB: {
                    switch patch.digits.highlightWrongRGB! {
                    case .color(let color): color
                    case .disabled: nil
                    }
                }(),
                postStopVisibilitySeconds: patch.digits.postStopVisibilitySeconds!,
                maskingCharacter: patch.digits.maskingCharacter!,
                annotationHeightArcmin: patch.annotation.heightDegrees! * 60,
                annotationFontName: patch.annotation.fontName!,
                annotationFontRGB: patch.annotation.fontRGB!,
                timeBarFillRGB: patch.timeBar.fillRGB!,
                timeBarHeightArcmin: patch.timeBar.heightDegrees! * 60,
                timeBarCornerRadiusArcmin: patch.timeBar.cornerRadiusDegrees! * 60,
                timeBarBackRGB: patch.timeBar.backRGB!,
                timeBarBackHeightArcmin: patch.timeBar.backHeightDegrees! * 60,
                timeBarBackCornerRadiusArcmin: patch.timeBar.backCornerRadiusDegrees! * 60,
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
                fovZoomedWidthDegrees: {
                    switch patch.fov.zoomedWidthDegrees! {
                    case .degrees(let degrees): degrees
                    case .disabled: nil
                    }
                }(),
                fovZoomedHeightDegrees: {
                    switch patch.fov.zoomedHeightDegrees! {
                    case .degrees(let degrees): degrees
                    case .disabled: nil
                    }
                }(),
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

private enum ConditionFactorExpander {
    private struct ParallelArray {
        let path: String
        let count: Int
    }

    private static let rgbKeys: Set<String> = [
        "rgb", "font_rgb", "fill_rgb", "back_rgb", "gutter_rgb", "inner_margin_rgb",
        "highlight_correct_rgb", "highlight_wrong_rgb"
    ]

    static func expandConditions(in data: Data) throws -> Data {
        let rawRoot: Any
        do {
            rawRoot = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ExperimentError.invalidConfiguration("Malformed JSON: \(error.localizedDescription)")
        }
        guard var root = rawRoot as? [String: Any],
              let rawConditions = root["conditions"] as? [Any] else {
            return data
        }

        if let master = root["master_condition_template"] {
            var masterArrays: [ParallelArray] = []
            try collectParallelArrays(
                in: master,
                key: nil,
                path: "$.master_condition_template",
                into: &masterArrays
            )
            if let first = masterArrays.first {
                throw ExperimentError.invalidConfiguration(
                    "\(first.path) uses a factor array; master_condition_template values must be scalar."
                )
            }
        }

        var expandedConditions: [Any] = []
        for (conditionIndex, rawCondition) in rawConditions.enumerated() {
            let conditionPath = "$.conditions[\(conditionIndex)]"
            guard var baseCondition = rawCondition as? [String: Any] else {
                throw ExperimentError.invalidConfiguration("\(conditionPath) must be an object.")
            }
            let rawFactors = baseCondition.removeValue(forKey: "factors")
            let factors: [Any]
            if let rawFactors {
                guard let values = rawFactors as? [Any], !values.isEmpty else {
                    throw ExperimentError.invalidConfiguration(
                        "\(conditionPath).factors must be a nonempty array."
                    )
                }
                factors = values
            } else {
                factors = []
            }

            var baseArrays: [ParallelArray] = []
            try collectParallelArrays(
                in: baseCondition,
                key: nil,
                path: conditionPath,
                into: &baseArrays
            )
            if let misplaced = baseArrays.first(where: { !isSchedulingPath($0.path) }) {
                throw ExperimentError.invalidConfiguration(
                    "\(misplaced.path) is a factor array; condition factor arrays must be inside factors."
                )
            }
            try validateMatchingLengths(
                baseArrays,
                groupName: "scheduling",
                conditionPath: conditionPath
            )
            let schedulingCount = baseArrays.map(\.count).max() ?? 1

            var factorCombinations: [[String: Any]] = [[:]]
            for (factorIndex, rawFactor) in factors.enumerated() {
                let factorPath = "\(conditionPath).factors[\(factorIndex)]"
                guard let factor = rawFactor as? [String: Any] else {
                    throw ExperimentError.invalidConfiguration("\(factorPath) must be an object.")
                }
                let levels = try expandFactor(factor, path: factorPath)
                var crossed: [[String: Any]] = []
                for combination in factorCombinations {
                    for level in levels {
                        var merged = combination
                        try merge(
                            level,
                            into: &merged,
                            rejectingConflicts: true,
                            path: conditionPath
                        )
                        crossed.append(merged)
                    }
                }
                factorCombinations = crossed
            }

            for schedulingIndex in 0..<schedulingCount {
                guard let scheduledCondition = selectParallelValue(
                    from: baseCondition,
                    key: nil,
                    index: schedulingIndex
                ) as? [String: Any] else {
                    throw ExperimentError.invalidConfiguration("\(conditionPath) must be an object.")
                }
                for combination in factorCombinations {
                    var expandedCondition = scheduledCondition
                    try merge(
                        combination,
                        into: &expandedCondition,
                        rejectingConflicts: false,
                        path: conditionPath
                    )
                    expandedConditions.append(expandedCondition)
                }
            }
        }
        root["conditions"] = expandedConditions
        do {
            return try JSONSerialization.data(withJSONObject: root)
        } catch {
            throw ExperimentError.invalidConfiguration(
                "The expanded protocol could not be serialized: \(error.localizedDescription)"
            )
        }
    }

    private static func expandFactor(
        _ factor: [String: Any],
        path: String
    ) throws -> [[String: Any]] {
        var arrays: [ParallelArray] = []
        try collectParallelArrays(in: factor, key: nil, path: path, into: &arrays)
        try validateMatchingLengths(arrays, groupName: "factor", conditionPath: path)
        let levelCount = arrays.map(\.count).max() ?? 1
        return try (0..<levelCount).map { levelIndex in
            guard let level = selectParallelValue(
                from: factor,
                key: nil,
                index: levelIndex
            ) as? [String: Any] else {
                throw ExperimentError.invalidConfiguration("\(path) must be an object.")
            }
            return level
        }
    }

    private static func collectParallelArrays(
        in value: Any,
        key: String?,
        path: String,
        into arrays: inout [ParallelArray]
    ) throws {
        if let dictionary = value as? [String: Any] {
            for (childKey, childValue) in dictionary {
                try collectParallelArrays(
                    in: childValue,
                    key: childKey,
                    path: "\(path).\(childKey)",
                    into: &arrays
                )
            }
            return
        }
        guard let array = value as? [Any], !isAtomic(array, key: key) else { return }
        guard !array.isEmpty else {
            throw ExperimentError.invalidConfiguration(
                "\(path) is an empty factor or scheduling array; provide at least one value."
            )
        }
        arrays.append(
            .init(
                path: path,
                count: array.count
            )
        )
    }

    private static func selectParallelValue(
        from value: Any,
        key: String?,
        index: Int
    ) -> Any {
        if let dictionary = value as? [String: Any] {
            var selected: [String: Any] = [:]
            for (childKey, childValue) in dictionary {
                selected[childKey] = selectParallelValue(
                    from: childValue,
                    key: childKey,
                    index: index
                )
            }
            return selected
        }
        guard let array = value as? [Any], !isAtomic(array, key: key) else { return value }
        if array.count == 1 {
            return array[0]
        }
        return array[index]
    }

    private static func validateMatchingLengths(
        _ arrays: [ParallelArray],
        groupName: String,
        conditionPath: String
    ) throws {
        let maximum = arrays.map(\.count).max() ?? 1
        guard arrays.contains(where: { $0.count != 1 && $0.count != maximum }) else { return }
        let lengths = arrays
            .map { "\($0.path) has \($0.count)" }
            .joined(separator: "; ")
        throw ExperimentError.invalidConfiguration(
            "\(conditionPath) contains \(groupName) arrays with different lengths; \(lengths)."
        )
    }

    private static func isSchedulingPath(_ path: String) -> Bool {
        path.contains(".scheduling.")
    }

    private static func merge(
        _ overlay: [String: Any],
        into base: inout [String: Any],
        rejectingConflicts: Bool,
        path: String
    ) throws {
        for (key, overlayValue) in overlay {
            let childPath = "\(path).\(key)"
            if var baseDictionary = base[key] as? [String: Any],
               let overlayDictionary = overlayValue as? [String: Any] {
                try merge(
                    overlayDictionary,
                    into: &baseDictionary,
                    rejectingConflicts: rejectingConflicts,
                    path: childPath
                )
                base[key] = baseDictionary
            } else if rejectingConflicts, base[key] != nil {
                throw ExperimentError.invalidConfiguration(
                    "\(childPath) is defined by more than one factor; factor properties must not overlap."
                )
            } else {
                base[key] = overlayValue
            }
        }
    }

    private static func isAtomic(_ array: [Any], key: String?) -> Bool {
        guard let key else { return false }
        return rgbKeys.contains(key)
            && array.count == 3
            && array.allSatisfy { $0 is NSNumber }
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
                "instructions", "debriefing_title", "debriefing", "task_mode",
                "sounds", "input", "master_condition_template", "conditions"
            ],
            path: "$"
        )
        guard let schemaVersion = root["schema_version"] as? Int else {
            throw invalid("$.schema_version", "must be an integer.")
        }
        guard schemaVersion == 10 else {
            throw ExperimentError.invalidConfiguration(
                "schema_version \(schemaVersion) is unsupported; this app requires version 10."
            )
        }
        guard let rawInput = root["input"] else {
            throw invalid("$.input", "is required.")
        }
        try section(root["sounds"], path: "$.sounds", allowed: ["reveal", "stop_timer", "correct", "wrong", "timer", "final"])
        if let rawSounds = root["sounds"] {
            let sounds = try dictionary(rawSounds, path: "$.sounds")
            for name in ["reveal", "stop_timer", "correct", "wrong", "timer", "final"] {
                try section(sounds[name], path: "$.sounds.\(name)", allowed: ["file", "volume"])
            }
        }
        try section(
            rawInput,
            path: "$.input",
            allowed: ["start_digits", "stop_command", "cross_digits", "speech"]
        )
        let input = try dictionary(rawInput, path: "$.input")
        try section(
            input["speech"],
            path: "$.input.speech",
            allowed: ["aliases", "max_interdigit_pause_seconds"]
        )
        if let rawSpeech = input["speech"] {
            let speech = try dictionary(rawSpeech, path: "$.input.speech")
            if let rawAliases = speech["aliases"] {
                let aliases = try dictionary(rawAliases, path: "$.input.speech.aliases")
                try keys(aliases, allowed: Set((0...9).map(String.init)), path: "$.input.speech.aliases")
            }
        }
        guard let rawMaster = root["master_condition_template"] else {
            throw invalid("$.master_condition_template", "is required.")
        }
        try definition(
            rawMaster,
            path: "$.master_condition_template",
            schedulingFields: false,
            factorFields: false
        )
        guard let rawConditions = root["conditions"] as? [Any] else {
            throw invalid("$.conditions", "must be an array.")
        }
        for (index, rawCondition) in rawConditions.enumerated() {
            let path = "$.conditions[\(index)]"
            try definition(
                rawCondition,
                path: path,
                schedulingFields: true,
                factorFields: true
            )
        }
    }

    private static func definition(
        _ rawDefinition: Any,
        path: String,
        schedulingFields: Bool,
        factorFields: Bool
    ) throws {
            let condition = try dictionary(rawDefinition, path: path)
            var allowed: Set<String> = [
                "random_seed", "passthrough_dimming", "digits", "annotation", "timer_bar", "tiles", "surround", "fov"
            ]
            if schedulingFields {
                allowed.insert("scheduling")
            }
            if factorFields {
                allowed.insert("factors")
            }
            try keys(condition, allowed: allowed, path: path)
            try section(
                condition["scheduling"],
                path: "\(path).scheduling",
                allowed: ["repeats", "block_nr"]
            )
            if let rawFactors = condition["factors"] {
                guard let factors = rawFactors as? [Any], !factors.isEmpty else {
                    throw invalid("\(path).factors", "must be a nonempty array.")
                }
                for (index, factor) in factors.enumerated() {
                    try definition(
                        factor,
                        path: "\(path).factors[\(index)]",
                        schedulingFields: false,
                        factorFields: false
                    )
                }
            }
            try section(
                condition["digits"],
                path: "\(path).digits",
                allowed: ["height_degrees", "font_name", "rgb", "random_method", "highlight_correct_rgb", "highlight_wrong_rgb", "post_stop_visibility_seconds", "masking_character"]
            )
            try section(
                condition["annotation"],
                path: "\(path).annotation",
                allowed: ["height_degrees", "font_name", "font_rgb"]
            )
            try section(
                condition["timer_bar"],
                path: "\(path).timer_bar",
                allowed: ["fill_rgb", "height_degrees", "corner_radius_degrees", "back_rgb", "back_height_degrees", "back_corner_radius_degrees"]
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
                allowed: ["eye", "mode", "peak_opacity", "width_degrees", "height_degrees", "zoomed_width_degrees", "zoomed_height_degrees", "horizontal_offset_degrees", "vertical_offset_degrees", "distance_meters"]
            )
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
