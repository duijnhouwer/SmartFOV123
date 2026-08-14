import CoreFoundation
import Foundation

@MainActor
final class ResultFileWriter {
    private(set) var fileURL: URL?
    private var completedTrials: [CompletedTrial] = []
    private let documentsURLOverride: URL?
    private let now: () -> Date

    init(
        documentsURL: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        documentsURLOverride = documentsURL
        self.now = now
    }

    @discardableResult
    func appendCompletedTrial(_ experiment: Experiment) throws -> URL {
        let fileURL = try sessionFileURL()
        let trial = CompletedTrial(experiment: experiment)
        let document = ResultDocument(trials: completedTrials + [trial])

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

        completedTrials.append(trial)
        return fileURL
    }

    private func sessionFileURL() throws -> URL {
        if let fileURL {
            return fileURL
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
            "result_\(formatter.string(from: now())).json",
            isDirectory: false
        )
        guard !fileManager.fileExists(atPath: candidateURL.path) else {
            throw ResultFileError.fileAlreadyExists(candidateURL)
        }

        fileURL = candidateURL
        print("MobiWordFinder results file: \(candidateURL.path)")
        return candidateURL
    }
}

private struct ResultDocument: Encodable {
    let trials: [CompletedTrial]
}

private struct CompletedTrial: Encodable {
    let name: String
    let definition: Definition

    init(experiment: Experiment) {
        name = "trial\(experiment.trialNumber)"
        definition = Definition(experiment: experiment)
    }

    struct Definition: Encodable {
        let conditionName: String
        let blockNumber: Int
        let randomSeed: UInt64
        let digits: Digits
        let boxes: Boxes
        let fov: FOV
        let speech: Speech

        init(experiment: Experiment) {
            let configuration = experiment.configuration
            let stimulus = configuration.stimulus
            conditionName = experiment.conditionName
            blockNumber = experiment.blockNumber
            randomSeed = stimulus.randomSeed
            digits = .init(
                heightDegrees: stimulus.digitHeightArcmin / 60,
                fontName: stimulus.digitFontName,
                rgb: stimulus.digitRGB.array,
                randomMethod: stimulus.digitRandomMethod.rawValue
            )
            boxes = .init(
                widthDegrees: stimulus.digitBoxWidthArcmin / 60,
                heightDegrees: stimulus.digitBoxHeightArcmin / 60,
                strokeDegrees: stimulus.digitBoxStrokeArcmin / 60,
                fillRGB: stimulus.digitBoxFillRGB.array,
                strokeRGB: stimulus.digitBoxStrokeRGB.array,
                numberHorizontal: stimulus.numberOfDigitBoxesHorizontal,
                numberVertical: stimulus.numberOfDigitBoxesVertical
            )
            fov = .init(
                eye: stimulus.eye.rawValue,
                mode: configuration.display.mode.rawValue,
                peakOpacity: configuration.display.peakOpacity,
                widthDegrees: stimulus.fovWidthDegrees,
                heightDegrees: stimulus.fovHeightDegrees,
                horizontalOffsetDegrees: stimulus.fovHorizontalOffsetDegrees,
                verticalOffsetDegrees: stimulus.fovVerticalOffsetDegrees,
                backgroundRGB: stimulus.fovBackgroundRGB.array,
                borderStrokeArcmin: stimulus.fovBorderStrokeArcmin,
                borderRGB: stimulus.fovBorderRGB.array,
                distanceMeters: stimulus.distanceMeters
            )
            speech = .init(aliases: configuration.speech.digitAliases)
        }

        private enum CodingKeys: String, CodingKey {
            case digits, boxes, fov, speech
            case conditionName = "condition_name"
            case blockNumber = "block_nr"
            case randomSeed = "random_seed"
        }
    }

    struct Digits: Encodable {
        let heightDegrees: Float
        let fontName: String
        let rgb: [Float]
        let randomMethod: String

        private enum CodingKeys: String, CodingKey {
            case rgb
            case heightDegrees = "height_degrees"
            case fontName = "font_name"
            case randomMethod = "random_method"
        }
    }

    struct Boxes: Encodable {
        let widthDegrees: Float
        let heightDegrees: Float
        let strokeDegrees: Float
        let fillRGB: [Float]
        let strokeRGB: [Float]
        let numberHorizontal: Int
        let numberVertical: Int

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

    struct FOV: Encodable {
        let eye: String
        let mode: String
        let peakOpacity: Float
        let widthDegrees: Float
        let heightDegrees: Float
        let horizontalOffsetDegrees: Float
        let verticalOffsetDegrees: Float
        let backgroundRGB: [Float]
        let borderStrokeArcmin: Float
        let borderRGB: [Float]
        let distanceMeters: Float

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

    struct Speech: Encodable {
        let aliases: [String: [String]]
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
        let keys = dictionary.keys.sorted()
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
    case documentsDirectoryUnavailable(Error)
    case couldNotCreateDirectory(URL, Error)
    case fileAlreadyExists(URL)
    case couldNotEncode(Error)
    case couldNotWrite(URL, Error)
    case invalidEncodedJSON

    var errorDescription: String? {
        switch self {
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
