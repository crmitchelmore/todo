import Foundation

public enum URLSummaryCapture {
    public static let source = "url-summary"

    public static func urlOnly(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let url = components.url
        else { return nil }
        return url.absoluteString
    }
}

