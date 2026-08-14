import Foundation

@MainActor
final class ResultFileWriter {
    private(set) var fileURL: URL?

    @discardableResult
    func appendCompletedTrial(number: Int) throws -> URL {
        let fileURL = try sessionFileURL()
        let data = Data("trial\(number)\n".utf8)
        let handle: FileHandle

        do {
            handle = try FileHandle(forWritingTo: fileURL)
        } catch {
            throw ResultFileError.couldNotOpen(fileURL, error)
        }
        defer { try? handle.close() }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            throw ResultFileError.couldNotAppend(fileURL, error)
        }

        return fileURL
    }

    private func sessionFileURL() throws -> URL {
        if let fileURL {
            return fileURL
        }

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
            throw ResultFileError.documentsDirectoryUnavailable(error)
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
            "result_\(formatter.string(from: Date())).json",
            isDirectory: false
        )
        guard !fileManager.fileExists(atPath: candidateURL.path) else {
            throw ResultFileError.fileAlreadyExists(candidateURL)
        }
        guard fileManager.createFile(atPath: candidateURL.path, contents: Data()) else {
            throw ResultFileError.couldNotCreateFile(candidateURL)
        }

        fileURL = candidateURL
        print("MobiWordFinder results file: \(candidateURL.path)")
        return candidateURL
    }
}

private enum ResultFileError: LocalizedError {
    case documentsDirectoryUnavailable(Error)
    case couldNotCreateDirectory(URL, Error)
    case fileAlreadyExists(URL)
    case couldNotCreateFile(URL)
    case couldNotOpen(URL, Error)
    case couldNotAppend(URL, Error)

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable(let error):
            return "The app's Documents directory is unavailable: \(error.localizedDescription)"
        case .couldNotCreateDirectory(let url, let error):
            return "Couldn't create \(url.lastPathComponent): \(error.localizedDescription)"
        case .fileAlreadyExists(let url):
            return "Refusing to overwrite the existing file \(url.lastPathComponent)."
        case .couldNotCreateFile(let url):
            return "Couldn't create \(url.lastPathComponent)."
        case .couldNotOpen(let url, let error):
            return "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        case .couldNotAppend(let url, let error):
            return "Couldn't append to \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
