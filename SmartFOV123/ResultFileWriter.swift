import CoreFoundation
import Foundation

@MainActor
final class ResultFileWriter {
    private(set) var fileURL: URL?
    private var completedTrials: [CompletedTrial] = []
    private var experimentMetadata: ResultExperiment?
    private var firstTargetReadMS: UInt64?
    private var isFinalized = false
    private let documentsURLOverride: URL?
    private let now: () -> Date

    init(
        documentsURL: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        documentsURLOverride = documentsURL
        self.now = now
    }

    func beginExperiment(
        protocolName: String,
        subjectNumber: String,
        taskMode: TaskMode,
        input: InputConfiguration,
        sounds: SoundsConfiguration,
        forcedVoiceInput: Bool,
        startDate: Date? = nil
    ) {
        let startDate = startDate ?? now()
        experimentMetadata = .init(
            protocolName: protocolName,
            subjectNumber: subjectNumber,
            taskMode: taskMode,
            input: input,
            sounds: sounds,
            forcedVoiceInput: forcedVoiceInput,
            startDate: startDate
        )
        completedTrials = []
        firstTargetReadMS = nil
        fileURL = nil
        isFinalized = false
    }

    func appendCompletedTrial(
        _ experiment: Experiment,
        results: CompletedTrialResults
    ) throws {
        guard experimentMetadata != nil else {
            throw ResultFileError.experimentMetadataMissing
        }
        completedTrials.append(CompletedTrial(experiment: experiment, results: results))
    }

    func markFirstTargetRead(atMS milliseconds: UInt64) {
        if firstTargetReadMS == nil {
            firstTargetReadMS = milliseconds
        }
    }

    func finishTimedExperiment(
        score: Int,
        durationSeconds: Int,
        endTimeMS: UInt64
    ) throws {
        try finish(
            endTimeMS: endTimeMS,
            summary: .init(
                score: score,
                durationSeconds: durationSeconds,
                endTimeMS: endTimeMS
            )
        )
    }

    func finishFixedExperiment(endTimeMS: UInt64) throws {
        try finish(endTimeMS: endTimeMS, summary: nil)
    }

    func finishInterruptedExperiment(endTimeMS: UInt64) throws {
        try finish(endTimeMS: endTimeMS, summary: nil)
    }

    private func finish(endTimeMS: UInt64, summary: ResultSummary?) throws {
        guard !isFinalized else { return }
        guard let firstTargetReadMS else { return }
        guard let experimentMetadata else {
            throw ResultFileError.experimentMetadataMissing
        }
        let durationSeconds = Int(endTimeMS.saturatingSubtract(firstTargetReadMS) / 1_000)
        let outputURL = try sessionFileURL(durationSeconds: durationSeconds)
        try write(
            .init(
                experiment: experimentMetadata,
                trials: completedTrials,
                summary: summary
            ),
            to: outputURL
        )
        isFinalized = true
    }

    private func write(_ document: ResultDocument, to fileURL: URL) throws {
        let data: Data
        do {
            data = try JSONPrettyPrinter.encode(document)
        } catch {
            throw ResultFileError.couldNotEncode(error)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ResultFileError.couldNotWrite(fileURL, error)
        }
    }

    private func sessionFileURL(durationSeconds: Int) throws -> URL {
        if let fileURL {
            return fileURL
        }

        guard let experimentMetadata else {
            throw ResultFileError.experimentMetadataMissing
        }
        let fileManager = FileManager.default
        let documentsURL: URL
        if let documentsURLOverride {
            documentsURL = documentsURLOverride
        } else {
            do {
                documentsURL = try fileManager.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
            } catch {
                throw ResultFileError.documentsDirectoryUnavailable(error)
            }
        }

        let resultsDirectoryURL = documentsURL.appendingPathComponent(
            "Results",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: resultsDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ResultFileError.couldNotCreateDirectory(resultsDirectoryURL, error)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd_HHmmss"

        let candidateURL = resultsDirectoryURL.appendingPathComponent(
            "\(Self.filenameComponent(experimentMetadata.protocolName))_p\(Self.filenameComponent(experimentMetadata.subjectNumber))_\(formatter.string(from: experimentMetadata.timestamp))_\(durationSeconds)s.json",
            isDirectory: false
        )
        guard !fileManager.fileExists(atPath: candidateURL.path) else {
            throw ResultFileError.fileAlreadyExists(candidateURL)
        }

        fileURL = candidateURL
        print("SmartFOV123 results file: \(candidateURL.path)")
        return candidateURL
    }

    private static func filenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
            .reduce(into: "") { $0.append($1) }
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}

private struct ResultDocument: Encodable {
    let experiment: ResultExperiment
    let trials: [CompletedTrial]
    let summary: ResultSummary?
}

private struct ResultSummary: Encodable {
    let score: Int
    let durationSeconds: Int
    let endTimeMS: UInt64

    private enum CodingKeys: String, CodingKey {
        case score
        case durationSeconds = "duration_seconds"
        case endTimeMS = "end_time_ms"
    }
}

private struct ResultExperiment: Encodable {
    let application = "SmartFOV123"
    let protocolName: String
    let subjectNumber: String
    let taskMode: String?
    let input: InputConfiguration
    let sounds: SoundsConfiguration
    let forcedVoiceInput: Bool
    let startDate: String
    let startTime: String
    let timestamp: Date

    init(
        protocolName: String,
        subjectNumber: String,
        taskMode: TaskMode,
        input: InputConfiguration,
        sounds: SoundsConfiguration,
        forcedVoiceInput: Bool,
        startDate: Date
    ) {
        self.protocolName = protocolName
        self.subjectNumber = subjectNumber
        self.taskMode = taskMode.durationSeconds == nil ? nil : taskMode.rawValue
        self.input = input
        self.sounds = sounds
        self.forcedVoiceInput = forcedVoiceInput
        timestamp = startDate

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = .autoupdatingCurrent
        dateFormatter.dateFormat = "yyyy-MM-dd"
        self.startDate = dateFormatter.string(from: startDate)

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.timeZone = .autoupdatingCurrent
        timeFormatter.dateFormat = "HH:mm:ssZZZZZ"
        self.startTime = timeFormatter.string(from: startDate)
    }

    private enum CodingKeys: String, CodingKey {
        case application
        case protocolName = "protocol_name"
        case subjectNumber = "subject_number"
        case taskMode = "task_mode"
        case input
        case sounds
        case forcedVoiceInput = "forced_voice_input"
        case startDate = "start_date"
        case startTime = "start_time"
    }
}

enum TrialResponse: String, Encodable {
    case correct
    case wrong
    case timedOut = "timed_out"
}

struct CompletedTrialResults: Encodable {
    let absoluteTrialStartMS: UInt64
    let digitRevealMS: Int64
    let timerStartMS: Int64
    let stopSignalStartMS: Int64?
    let timerStopMS: Int64
    let response: TrialResponse
    let speech: [SpeechDetection]
    let keyboard: [KeyboardDetection]

    init(
        absoluteTrialStartMS: UInt64,
        digitRevealMS: UInt64,
        timerStartMS: UInt64,
        stopSignalStartMS: UInt64?,
        timerStopMS: UInt64,
        response: TrialResponse,
        speech: [SpeechDetection],
        keyboard: [KeyboardDetection]
    ) {
        self.absoluteTrialStartMS = absoluteTrialStartMS
        let signedTrialStartMS = Int64(absoluteTrialStartMS)
        self.digitRevealMS = Int64(digitRevealMS) - signedTrialStartMS
        self.timerStartMS = Int64(timerStartMS) - signedTrialStartMS
        self.stopSignalStartMS = stopSignalStartMS.map { Int64($0) - signedTrialStartMS }
        self.timerStopMS = Int64(timerStopMS) - signedTrialStartMS
        self.response = response
        self.speech = speech.map {
            .init(
                id: $0.id,
                token: $0.token,
                recognizedMS: $0.recognizedMS - signedTrialStartMS
            )
        }
        self.keyboard = keyboard.map {
            .init(
                key: $0.key,
                startMS: $0.startMS - signedTrialStartMS
            )
        }
    }

    struct SpeechDetection: Encodable {
        let id: String
        let token: String
        let recognizedMS: Int64

        func encode(to encoder: Encoder) throws {
            var outer = encoder.container(keyedBy: DynamicCodingKey.self)
            try outer.encode(
                SpeechTiming(recognizedMS: recognizedMS),
                forKey: .init(token)
            )
        }
    }

    struct KeyboardDetection: Encodable {
        let key: String
        let startMS: Int64

        func encode(to encoder: Encoder) throws {
            var outer = encoder.container(keyedBy: DynamicCodingKey.self)
            try outer.encode(
                KeyboardTiming(startMS: startMS),
                forKey: .init(key)
            )
        }
    }

    private struct SpeechTiming: Encodable {
        let recognizedMS: Int64

        private enum CodingKeys: String, CodingKey {
            case recognizedMS = "recognized_ms"
        }
    }

    private struct KeyboardTiming: Encodable {
        let startMS: Int64

        private enum CodingKeys: String, CodingKey {
            case startMS = "start_ms"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case speech, keyboard
        case absoluteTrialStartMS = "absolute_trial_start_ms"
        case digitRevealMS = "digit_reveal_ms"
        case timerStartMS = "timer_start_ms"
        case stopSignalStartMS = "stop_signal_start_ms"
        case timerStopMS = "timer_stop_ms"
        case response
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

private struct CompletedTrial: Encodable {
    let name: String
    let definition: Definition
    let seededStimulus: SeededStimulus
    let results: CompletedTrialResults

    init(experiment: Experiment, results: CompletedTrialResults) {
        name = "trial\(experiment.trialNumber)"
        definition = Definition(experiment: experiment)
        seededStimulus = SeededStimulus(experiment: experiment)
        self.results = results
    }

    private enum CodingKeys: String, CodingKey {
        case name, definition, results
        case seededStimulus = "seeded_stimulus"
    }

    struct SeededStimulus: Encodable {
        let targetNumber: Int
        let targetOrientation: String
        let responseNumber: Int
        let numberOfFirstTwoDigitDuplicates: Int
        let grid: [[Int]]

        init(experiment: Experiment) {
            let numberGrid = experiment.grid
            targetNumber = Int(numberGrid.targetNumber)!
            switch numberGrid.targetPlacement.orientation {
            case .horizontal:
                targetOrientation = "leftright"
            case .vertical:
                targetOrientation = "topdown"
            }
            responseNumber = Int(numberGrid.verificationCode)!
            numberOfFirstTwoDigitDuplicates = numberGrid.numberOfFirstTwoDigitDuplicates
            grid = (0..<numberGrid.rows).map { row in
                (0..<numberGrid.columns).map { column in
                    Int(numberGrid.digits[row * numberGrid.columns + column] - 48)
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case grid
            case targetNumber = "target_number"
            case targetOrientation = "target_orientation"
            case responseNumber = "response_number"
            case numberOfFirstTwoDigitDuplicates = "number_of_first_two_digit_duplicates"
        }
    }

    struct Definition: Encodable {
        let conditionNumber: Int
        let blockNumber: Int
        let randomSeed: UInt64
        let passthroughDimming: Double
        let maxSearchTimeSeconds: Float
        let digits: Digits
        let annotation: Annotation
        let timerBar: TimerBar
        let tiles: Tiles
        let surround: Surround
        let fov: FOV

        init(experiment: Experiment) {
            let configuration = experiment.configuration
            let stimulus = configuration.stimulus
            conditionNumber = experiment.conditionNumber
            blockNumber = experiment.blockNumber
            randomSeed = experiment.randomSeed
            passthroughDimming = configuration.display.passthroughDimming
            maxSearchTimeSeconds = configuration.maxSearchTimeSeconds
            digits = .init(
                heightDegrees: stimulus.digitHeightArcmin / 60,
                fontName: stimulus.digitFontName,
                rgb: stimulus.digitRGB.array,
                randomMethod: stimulus.digitRandomMethod.rawValue,
                highlightCorrectRGB: stimulus.digitHighlightCorrectRGB.map {
                    .color($0.array)
                } ?? .disabled,
                highlightWrongRGB: stimulus.digitHighlightWrongRGB.map {
                    .color($0.array)
                } ?? .disabled,
                postStopVisibilitySeconds: stimulus.postStopVisibilitySeconds,
                maskingCharacter: stimulus.maskingCharacter
            )
            annotation = .init(
                heightDegrees: stimulus.annotationHeightArcmin / 60,
                fontName: stimulus.annotationFontName,
                fontRGB: stimulus.annotationFontRGB.array
            )
            timerBar = .init(
                fillRGB: stimulus.timeBarFillRGB.array,
                heightDegrees: stimulus.timeBarHeightArcmin / 60,
                cornerRadiusDegrees: stimulus.timeBarCornerRadiusArcmin / 60,
                backRGB: stimulus.timeBarBackRGB.array,
                backHeightDegrees: stimulus.timeBarBackHeightArcmin / 60,
                backCornerRadiusDegrees: stimulus.timeBarBackCornerRadiusArcmin / 60
            )
            tiles = .init(
                widthDegrees: stimulus.tileWidthArcmin / 60,
                heightDegrees: stimulus.tileHeightArcmin / 60,
                gutterDegrees: stimulus.tileGutterArcmin / 60,
                cornerRadiusDegrees: stimulus.tileCornerRadiusArcmin / 60,
                fillRGB: stimulus.tileFillRGB.array,
                gutterRGB: stimulus.tileGutterRGB.array,
                numberHorizontal: stimulus.numberOfTilesHorizontal,
                numberVertical: stimulus.numberOfTilesVertical
            )
            surround = .init(
                fillRGB: stimulus.surroundFillRGB.array,
                innerMarginRGB: stimulus.surroundInnerMarginRGB.array,
                innerMarginDegrees: stimulus.surroundInnerMarginArcmin / 60,
                innerCornerRadiusDegrees: stimulus.surroundInnerCornerRadiusArcmin / 60,
                outerCornerRadiusDegrees: stimulus.surroundOuterCornerRadiusArcmin / 60
            )
            fov = .init(
                eye: stimulus.eye.rawValue,
                mode: configuration.display.mode.rawValue,
                peakOpacity: configuration.display.peakOpacity,
                widthDegrees: stimulus.fovWidthDegrees,
                heightDegrees: stimulus.fovHeightDegrees,
                zoomedWidthDegrees: stimulus.fovZoomedWidthDegrees.map {
                    .degrees($0)
                } ?? .disabled,
                zoomedHeightDegrees: stimulus.fovZoomedHeightDegrees.map {
                    .degrees($0)
                } ?? .disabled,
                horizontalOffsetDegrees: stimulus.fovHorizontalOffsetDegrees,
                verticalOffsetDegrees: stimulus.fovVerticalOffsetDegrees,
                distanceMeters: stimulus.distanceMeters
            )
        }

        private enum CodingKeys: String, CodingKey {
            case digits, annotation, timerBar = "timer_bar", tiles, surround, fov
            case conditionNumber = "condition_nr"
            case blockNumber = "block_nr"
            case randomSeed = "random_seed"
            case passthroughDimming = "passthrough_dimming"
            case maxSearchTimeSeconds = "max_search_time_seconds"
        }
    }

    struct Digits: Encodable {
        enum Highlight: Encodable {
            case color([Float])
            case disabled

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .color(let rgb): try container.encode(rgb)
                case .disabled: try container.encode("disabled")
                }
            }
        }

        let heightDegrees: Float
        let fontName: String
        let rgb: [Float]
        let randomMethod: String
        let highlightCorrectRGB: Highlight
        let highlightWrongRGB: Highlight
        let postStopVisibilitySeconds: Float
        let maskingCharacter: String

        private enum CodingKeys: String, CodingKey {
            case rgb
            case heightDegrees = "height_degrees"
            case fontName = "font_name"
            case randomMethod = "random_method"
            case highlightCorrectRGB = "highlight_correct_rgb"
            case highlightWrongRGB = "highlight_wrong_rgb"
            case postStopVisibilitySeconds = "post_stop_visibility_seconds"
            case maskingCharacter = "masking_character"
        }
    }

    struct Annotation: Encodable {
        let heightDegrees: Float
        let fontName: String
        let fontRGB: [Float]

        private enum CodingKeys: String, CodingKey {
            case fontRGB = "font_rgb"
            case heightDegrees = "height_degrees"
            case fontName = "font_name"
        }
    }

    struct TimerBar: Encodable {
        let fillRGB: [Float]
        let heightDegrees: Float
        let cornerRadiusDegrees: Float
        let backRGB: [Float]
        let backHeightDegrees: Float
        let backCornerRadiusDegrees: Float

        private enum CodingKeys: String, CodingKey {
            case fillRGB = "fill_rgb"
            case heightDegrees = "height_degrees"
            case cornerRadiusDegrees = "corner_radius_degrees"
            case backRGB = "back_rgb"
            case backHeightDegrees = "back_height_degrees"
            case backCornerRadiusDegrees = "back_corner_radius_degrees"
        }
    }

    struct Tiles: Encodable {
        let widthDegrees: Float
        let heightDegrees: Float
        let gutterDegrees: Float
        let cornerRadiusDegrees: Float
        let fillRGB: [Float]
        let gutterRGB: [Float]
        let numberHorizontal: Int
        let numberVertical: Int

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

    struct Surround: Encodable {
        let fillRGB: [Float]
        let innerMarginRGB: [Float]
        let innerMarginDegrees: Float
        let innerCornerRadiusDegrees: Float
        let outerCornerRadiusDegrees: Float

        private enum CodingKeys: String, CodingKey {
            case fillRGB = "fill_rgb"
            case innerMarginRGB = "inner_margin_rgb"
            case innerMarginDegrees = "inner_margin_degrees"
            case innerCornerRadiusDegrees = "inner_corner_radius_degrees"
            case outerCornerRadiusDegrees = "outer_corner_radius_degrees"
        }
    }

    struct FOV: Encodable {
        enum Zoom: Encodable {
            case degrees(Float)
            case disabled

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .degrees(let value): try container.encode(value)
                case .disabled: try container.encode("disabled")
                }
            }
        }

        let eye: String
        let mode: String
        let peakOpacity: Float
        let widthDegrees: Float
        let heightDegrees: Float
        let zoomedWidthDegrees: Zoom
        let zoomedHeightDegrees: Zoom
        let horizontalOffsetDegrees: Float
        let verticalOffsetDegrees: Float
        let distanceMeters: Float

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

}

private enum JSONPrettyPrinter {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let compactData = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: compactData)
        let text = try render(object, level: 0) + "\n"
        return Data(text.utf8)
    }

    private static func render(_ value: Any, level: Int) throws -> String {
        if let dictionary = value as? [String: Any] {
            return try render(dictionary, level: level)
        }
        if let array = value as? [Any] {
            return try render(array, level: level)
        }
        return try renderScalar(value)
    }

    private static func render(_ dictionary: [String: Any], level: Int) throws -> String {
        guard !dictionary.isEmpty else { return "{}" }
        let keys = orderedKeys(for: dictionary)
        let childIndent = indentation(level + 1)
        let lines = try keys.enumerated().map { index, key in
            let renderedValue = try render(dictionary[key]!, level: level + 1)
            let comma = index == keys.count - 1 ? "" : ","
            return "\(childIndent)\(try renderScalar(key)): \(renderedValue)\(comma)"
        }
        return "{\n\(lines.joined(separator: "\n"))\n\(indentation(level))}"
    }

    private static func render(_ array: [Any], level: Int) throws -> String {
        guard !array.isEmpty else { return "[]" }
        if array.allSatisfy(isScalar) {
            return "[\(try array.map(renderScalar).joined(separator: ", "))]"
        }
        if array.allSatisfy(isInlineCollection) {
            return "[\(try array.map(renderInlineCollection).joined(separator: ", "))]"
        }

        let childIndent = indentation(level + 1)
        let lines = try array.enumerated().map { index, value in
            let comma = index == array.count - 1 ? "" : ","
            return "\(childIndent)\(try render(value, level: level + 1))\(comma)"
        }
        return "[\n\(lines.joined(separator: "\n"))\n\(indentation(level))]"
    }

    private static func renderScalar(_ value: Any) throws -> String {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if value is NSNull {
            return "null"
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ResultFileError.invalidEncodedJSON
        }
        return text
    }

    private static func isScalar(_ value: Any) -> Bool {
        value is String || value is NSNumber || value is NSNull
    }

    private static func isInlineCollection(_ value: Any) -> Bool {
        if let array = value as? [Any] {
            return array.allSatisfy(isScalar)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.allSatisfy(isScalar)
        }
        return false
    }

    private static func renderInlineCollection(_ value: Any) throws -> String {
        if let array = value as? [Any] {
            return "[\(try array.map(renderScalar).joined(separator: ", "))]"
        }
        if let dictionary = value as? [String: Any] {
            let entries = try orderedKeys(for: dictionary).map { key in
                "\(try renderScalar(key)): \(try renderScalar(dictionary[key]!))"
            }
            return "{\(entries.joined(separator: ", "))}"
        }
        throw ResultFileError.invalidEncodedJSON
    }

    private static func orderedKeys(for dictionary: [String: Any]) -> [String] {
        let preferredOrder: [String]

        if dictionary.keys.contains("trials") {
            preferredOrder = ["experiment", "trials", "summary"]
        } else if dictionary.keys.contains("application") {
            preferredOrder = [
                "application", "protocol_name", "subject_number", "task_mode", "input", "sounds", "forced_voice_input",
                "start_date", "start_time"
            ]
        } else if dictionary.keys.contains("duration_seconds") {
            preferredOrder = ["score", "duration_seconds", "end_time_ms"]
        } else if dictionary.keys.contains("seeded_stimulus") {
            preferredOrder = ["name", "definition", "seeded_stimulus", "results"]
        } else if dictionary.keys.contains("condition_nr") {
            preferredOrder = [
                "condition_nr", "block_nr", "random_seed", "passthrough_dimming",
                "max_search_time_seconds", "digits", "annotation", "timer_bar",
                "tiles", "surround", "fov"
            ]
        } else if dictionary.keys.contains("correct") && dictionary.keys.contains("timer") {
            preferredOrder = ["correct", "wrong", "timer", "final"]
        } else if dictionary.keys.contains("start_digits") {
            preferredOrder = ["start_digits", "stop_command", "cross_digits", "speech"]
        } else if dictionary.keys.contains("target_number") {
            preferredOrder = [
                "target_number", "target_orientation", "response_number",
                "number_of_first_two_digit_duplicates", "grid"
            ]
        } else if dictionary.keys.contains("absolute_trial_start_ms") {
            preferredOrder = ["absolute_trial_start_ms", "digit_reveal_ms", "timer_start_ms", "stop_signal_start_ms", "timer_stop_ms", "response", "speech", "keyboard"]
        } else if dictionary.keys.contains("start_ms") {
            preferredOrder = ["start_ms"]
        } else if dictionary.keys.contains("recognized_ms") {
            preferredOrder = ["recognized_ms"]
        } else if dictionary.keys.contains("back_height_degrees") {
            preferredOrder = [
                "fill_rgb", "height_degrees", "corner_radius_degrees", "back_rgb",
                "back_height_degrees", "back_corner_radius_degrees"
            ]
        } else if dictionary.keys.contains("font_name") {
            preferredOrder = ["height_degrees", "font_name", "font_rgb", "rgb", "random_method", "highlight_correct_rgb", "highlight_wrong_rgb", "post_stop_visibility_seconds", "masking_character"]
        } else if dictionary.keys.contains("number_horizontal") {
            preferredOrder = [
                "width_degrees", "height_degrees", "gutter_degrees", "corner_radius_degrees",
                "fill_rgb", "gutter_rgb",
                "number_horizontal", "number_vertical"
            ]
        } else if dictionary.keys.contains("peak_opacity") {
            preferredOrder = [
                "eye", "mode", "peak_opacity", "width_degrees", "height_degrees",
                "zoomed_width_degrees", "zoomed_height_degrees",
                "horizontal_offset_degrees", "vertical_offset_degrees", "distance_meters"
            ]
        } else if dictionary.keys.contains("inner_margin_degrees") {
            preferredOrder = [
                "fill_rgb", "inner_margin_rgb", "inner_margin_degrees",
                "inner_corner_radius_degrees", "outer_corner_radius_degrees"
            ]
        } else if dictionary.keys.contains("aliases") {
            preferredOrder = ["aliases", "max_interdigit_pause_seconds"]
        } else {
            preferredOrder = []
        }

        let preferredKeys = preferredOrder.filter(dictionary.keys.contains)
        let remainingKeys = dictionary.keys.filter { !preferredOrder.contains($0) }.sorted()
        return preferredKeys + remainingKeys
    }

    private static func indentation(_ level: Int) -> String {
        String(repeating: "  ", count: level)
    }
}

private extension RGB {
    var array: [Float] {
        [red, green, blue]
    }
}

private enum ResultFileError: LocalizedError {
    case experimentMetadataMissing
    case documentsDirectoryUnavailable(Error)
    case couldNotCreateDirectory(URL, Error)
    case fileAlreadyExists(URL)
    case couldNotEncode(Error)
    case couldNotWrite(URL, Error)
    case invalidEncodedJSON

    var errorDescription: String? {
        switch self {
        case .experimentMetadataMissing:
            return "The participant number and experiment metadata haven't been confirmed yet."
        case .documentsDirectoryUnavailable(let error):
            return "The app's Documents directory is unavailable: \(error.localizedDescription)"
        case .couldNotCreateDirectory(let url, let error):
            return "Couldn't create \(url.lastPathComponent): \(error.localizedDescription)"
        case .fileAlreadyExists(let url):
            return "Refusing to overwrite the existing file \(url.lastPathComponent)."
        case .couldNotEncode(let error):
            return "Couldn't encode the completed trial: \(error.localizedDescription)"
        case .couldNotWrite(let url, let error):
            return "Couldn't write \(url.lastPathComponent): \(error.localizedDescription)"
        case .invalidEncodedJSON:
            return "The encoded result couldn't be converted to UTF-8 JSON."
        }
    }
}
