import Foundation

public enum RSSRuleValidation {
    public static func regularExpressionError(for value: String, enabled: Bool) -> String? {
        guard enabled, !value.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: value, options: [.caseInsensitive])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func isValidEpisodeFilter(_ value: String) -> Bool {
        guard !value.isEmpty else { return true }
        let pattern = #"^\d{1,4}x(?:\d{1,4}(?:-\d{0,4})?;)+$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        return expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    public static func lastMatchDate(from value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
