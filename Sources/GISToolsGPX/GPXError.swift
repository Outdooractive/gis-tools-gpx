import Foundation

/// Errors thrown by GPX reading, writing, and validation.
public enum GPXError: LocalizedError {

    /// The file could not be read.
    /// - Parameter detail: The underlying error description.
    case fileReadError(detail: String)

    /// The file could not be written.
    /// - Parameter detail: The underlying error description.
    case fileWriteError(detail: String)

    /// The XML could not be parsed.
    /// - Parameter detail: The underlying XML parser error.
    case invalidXML(detail: String)

    /// A string could not be created, likely due to an encoding issue.
    case invalidEncoding

    /// The parsed document is not a valid GPX 1.1 file.
    /// - Parameter detail: A description of the violation.
    case invalidGPX(detail: String)

    /// An unsupported GPX version was encountered.
    /// - Parameter version: The version string found in the file.
    case unsupportedVersion(version: String)

    /// The latitude or longitude value is out of range.
    /// - Parameter detail: A description.
    case invalidCoordinate(detail: String)

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .fileReadError(let detail):
            "Could not read GPX file: \(detail)"
        case .fileWriteError(let detail):
            "Could not write GPX file: \(detail)"
        case .invalidXML(let detail):
            "Invalid XML: \(detail)"
        case .invalidEncoding:
            "Invalid encoding"
        case .invalidGPX(let detail):
            "Invalid GPX: \(detail)"
        case .unsupportedVersion(let version):
            "Unsupported GPX version '\(version)'. Only version 1.1 is supported."
        case .invalidCoordinate(let detail):
            "Invalid coordinate: \(detail)"
        }
    }

}
