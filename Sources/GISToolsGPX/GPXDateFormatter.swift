import Foundation

/// Shared ISO 8601 date formatting used by the GPX typed API.
enum GPXDateFormatter {

    static func parse(_ string: String) -> Date? {
        let formatters: [ISO8601DateFormatter] = [
            isoFormatter(withOptions: [.withInternetDateTime, .withFractionalSeconds]),
            isoFormatter(withOptions: [.withInternetDateTime]),
        ]
        for f in formatters {
            if let date = f.date(from: string) { return date }
        }
        return nil
    }

    static func format(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func isoFormatter(
        withOptions options: ISO8601DateFormatter.Options
    ) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = options
        return f
    }

}
