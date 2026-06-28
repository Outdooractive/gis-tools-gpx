import Foundation

/// Helper to locate test-data GPX files in the Swift package bundle.
enum TestData {

    /// Returns the URL of a GPX file in the `TestData` directory.
    static func url(name: String) -> URL? {
        let fileNameParts = name.split(separator: ".")
        let baseName = fileNameParts.count == 1
            ? name
            : fileNameParts.dropLast().joined(separator: ".")
        let ext = fileNameParts.count > 1
            ? ".\(fileNameParts.last!)"
            : ".gpx"

        return Bundle.module.url(
            forResource: baseName,
            withExtension: String(ext.dropFirst()),
            subdirectory: "TestData")
    }

}
