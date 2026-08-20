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
        startDate: Date? = nil
    ) {
        let startDate = startDate ?? now()
        experimentMetadata = .init(
            protocolName: protocolName,
            subjectNumber: subjectNumber,
            taskMode: taskMode,
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
    let startDate: String
    let startTime: String
    let timestamp: Date

    init(
        protocolName: String,
        subjectNumber: String,
        taskMode: TaskMode,
        startDate: Date
    ) {
        self.protocolName = protocolName
        self.subjectNumber = subjectNumber
        self.taskMode = taskMode.durationSeconds == nil ? nil : taskMode.rawValue
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
        case startDate = "start_date"
        case startTime = "start_time"
    }
}

struct CompletedTrialResults: Encodable {
    let startTimeMS: UInt64
    let digitRevealMS: UInt64
    let targetFoundMS: UInt64
    let speech: [SpeechDetection]

    struct SpeechDetection: Encodable {
        let utterance: String
        let ms: UInt64
    }

    private enum CodingKeys: String, CodingKey {
        case speech
        case startTimeMS = "start_time_ms"
        case digitRevealMS = "digit_reveal_ms"
        case targetFoundMS = "target_found_ms"
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
        }
    }

    struct Definition: Encodable {
        let conditionNumber: Int
        let blockNumber: Int
        let randomSeed: UInt64
        let passthroughDimming: Double
        let digits: Digits
        let annotation: Annotation
        let timer: Timer
        let feedbackSounds: FeedbackSounds
        let tiles: Tiles
        let surround: Surround
        let fov: FOV
        let speech: Speech

        init(experiment: Experiment) {
            let configuration = experiment.configuration
            let stimulus = configuration.stimulus
            conditionNumber = experiment.conditionNumber
            blockNumber = experiment.blockNumber
            randomSeed = experiment.randomSeed
            passthroughDimming = configuration.display.passthroughDimming
            digits = .init(
                heightDegrees: stimulus.digitHeightArcmin / 60,
                fontName: stimulus.digitFontName,
                rgb: stimulus.digitRGB.array,
                randomMethod: stimulus.digitRandomMethod.rawValue,
                highlightRGB: stimulus.digitHighlightRGB.array,
                highlightFont: stimulus.digitHighlightFontName
            )
            annotation = .init(
                heightDegrees: stimulus.annotationHeightArcmin / 60,
                fontName: stimulus.annotationFontName,
                fontRGB: stimulus.annotationFontRGB.array
            )
            timer = .init(
                sausage: .init(
                    fillRGB: stimulus.timeBarFillRGB.array,
                    heightDegrees: stimulus.timeBarHeightArcmin / 60,
                    cornerRadiusDegrees: stimulus.timeBarCornerRadiusArcmin / 60,
                    backRGB: stimulus.timeBarBackRGB.array,
                    backHeightDegrees: stimulus.timeBarBackHeightArcmin / 60,
                    backCornerRadiusDegrees: stimulus.timeBarBackCornerRadiusArcmin / 60
                ),
                metronome: .init(
                    startSeconds: stimulus.metronomeStartSeconds,
                    beatsPerMinute: stimulus.metronomeBeatsPerMinute,
                    volume: stimulus.metronomeVolume
                ),
                finalGongVolume: stimulus.finalGongVolume
            )
            feedbackSounds = .init(
                correct: .init(
                    file: stimulus.correctFeedbackFile,
                    volume: stimulus.correctFeedbackVolume
                ),
                wrong: .init(
                    file: stimulus.wrongFeedbackFile,
                    volume: stimulus.wrongFeedbackVolume
                )
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
                zoomedWidthDegrees: stimulus.fovZoomedWidthDegrees,
                zoomedHeightDegrees: stimulus.fovZoomedHeightDegrees,
                horizontalOffsetDegrees: stimulus.fovHorizontalOffsetDegrees,
                verticalOffsetDegrees: stimulus.fovVerticalOffsetDegrees,
                distanceMeters: stimulus.distanceMeters
            )
            speech = .init(
                aliases: configuration.speech.digitAliases,
                resetSeconds: configuration.speech.resetSeconds
            )
        }

        private enum CodingKeys: String, CodingKey {
            case digits, annotation, timer, tiles, surround, fov, speech
            case feedbackSounds = "feedback_sounds"
            case conditionNumber = "condition_nr"
            case blockNumber = "block_nr"
            case randomSeed = "random_seed"
            case passthroughDimming = "passthrough_dimming"
        }
    }

    struct Digits: Encodable {
        let heightDegrees: Float
        let fontName: String
        let rgb: [Float]
        let randomMethod: String
        let highlightRGB: [Float]
        let highlightFont: String

        private enum CodingKeys: String, CodingKey {
            case rgb
            case heightDegrees = "height_degrees"
            case fontName = "font_name"
            case randomMethod = "random_method"
            case highlightRGB = "highlight_rgb"
            case highlightFont = "highlight_font"
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

    struct TimerSausage: Encodable {
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

    struct Timer: Encodable {
        let sausage: TimerSausage
        let metronome: Metronome
        let finalGongVolume: Float

        private enum CodingKeys: String, CodingKey {
            case sausage, metronome
            case finalGongVolume = "final_gong_volume"
        }
    }

    struct FeedbackSound: Encodable {
        let file: String
        let volume: Float
    }

    struct FeedbackSounds: Encodable {
        let correct: FeedbackSound
        let wrong: FeedbackSound
    }

    struct Metronome: Encodable {
        let startSeconds: [Int]
        let beatsPerMinute: [Int]
        let volume: Float

        private enum CodingKeys: String, CodingKey {
            case startSeconds = "start_seconds"
            case beatsPerMinute = "beats_per_minute"
            case volume
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
        let eye: String
        let mode: String
        let peakOpacity: Float
        let widthDegrees: Float
        let heightDegrees: Float
        let zoomedWidthDegrees: Float
        let zoomedHeightDegrees: Float
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

    struct Speech: Encodable {
        let aliases: [String: [String]]
        let resetSeconds: Float

        private enum CodingKeys: String, CodingKey {
            case aliases
            case resetSeconds = "reset_seconds"
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
                "application", "protocol_name", "subject_number", "task_mode",
                "start_date", "start_time"
            ]
        } else if dictionary.keys.contains("duration_seconds") {
            preferredOrder = ["score", "duration_seconds", "end_time_ms"]
        } else if dictionary.keys.contains("seeded_stimulus") {
            preferredOrder = ["name", "definition", "seeded_stimulus", "results"]
        } else if dictionary.keys.contains("condition_nr") {
            preferredOrder = [
                "condition_nr", "block_nr", "random_seed", "passthrough_dimming", "digits", "annotation", "timer", "feedback_sounds",
                "tiles", "surround", "fov", "speech"
            ]
        } else if dictionary.keys.contains("metronome") {
            preferredOrder = ["sausage", "metronome", "final_gong_volume"]
        } else if dictionary.keys.contains("beats_per_minute") {
            preferredOrder = ["start_seconds", "beats_per_minute", "volume"]
        } else if dictionary.keys.contains("target_number") {
            preferredOrder = ["target_number", "target_orientation", "response_number", "grid"]
        } else if dictionary.keys.contains("start_time_ms") {
            preferredOrder = ["start_time_ms", "digit_reveal_ms", "target_found_ms", "speech"]
        } else if dictionary.keys.contains("utterance") {
            preferredOrder = ["utterance", "ms"]
        } else if dictionary.keys.contains("back_height_degrees") {
            preferredOrder = [
                "fill_rgb", "height_degrees", "corner_radius_degrees", "back_rgb",
                "back_height_degrees", "back_corner_radius_degrees"
            ]
        } else if dictionary.keys.contains("font_name") {
            preferredOrder = ["height_degrees", "font_name", "font_rgb", "rgb", "random_method", "highlight_rgb", "highlight_font"]
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
            preferredOrder = ["aliases", "reset_seconds"]
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
