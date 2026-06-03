import Foundation

/// One item produced by parsing a pasted markdown / checkbox list.
public struct ParsedCaptureItem: Sendable, Equatable {
    /// Cleaned task text (marker, checkbox, and inline #tags removed).
    public var title: String
    /// True when the source line was a ticked checkbox (`- [x]`).
    public var isDone: Bool
    /// Tags to attach: ancestor "project" lines (from nesting) plus inline `#tags`.
    public var tags: [String]

    public init(title: String, isDone: Bool = false, tags: [String] = []) {
        self.title = title
        self.isDone = isDone
        self.tags = tags
    }
}

/// Parses a pasted block of text into individual capture items.
///
/// Recognises markdown bullet (`-`, `*`, `+`), numbered (`1.`, `2)`) and GitHub-style
/// checkbox (`- [ ]`, `- [x]`) lists. Indentation expresses nesting: each ancestor line's
/// text becomes a "project" tag on its descendants (so `Projects = tags`). Inline `#tags`
/// are extracted and stripped from the title. A ticked checkbox marks the item done.
///
/// Pure and deterministic so it can be unit-tested directly and shared by every client.
public enum MarkdownListParser {
    /// Returns one item per list line, or `nil` if the text does not look like a list
    /// (in which case the caller should treat it as a single ordinary capture).
    public static func parse(_ text: String) -> [ParsedCaptureItem]? {
        let rawLines = text.components(separatedBy: .newlines)
        var parsed: [(depth: Int, line: ListLine)] = []
        var nonEmptyCount = 0

        // Track indentation widths to derive a normalised nesting depth.
        var indentStack: [Int] = []

        for raw in rawLines {
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            nonEmptyCount += 1
            guard let line = ListLine.parse(raw) else {
                parsed.append((depth: -1, line: ListLine.nonList))
                continue
            }
            let depth = Self.depth(forIndent: line.indent, stack: &indentStack)
            parsed.append((depth: depth, line: line))
        }

        let listLines = parsed.filter { $0.line.isList }
        // Only treat as a list when list markers dominate — avoids exploding prose that
        // happens to contain a stray dash. A single checkbox still counts (done-import).
        let hasCheckbox = listLines.contains { $0.line.hasCheckbox }
        guard !listLines.isEmpty,
              listLines.count >= 2 || hasCheckbox,
              listLines.count * 2 >= nonEmptyCount
        else { return nil }

        // Build the ancestor stack as we walk so each item inherits its parents' titles as tags.
        var items: [ParsedCaptureItem] = []
        var ancestors: [(depth: Int, title: String)] = []

        for entry in parsed where entry.line.isList {
            let line = entry.line
            while let last = ancestors.last, last.depth >= entry.depth {
                ancestors.removeLast()
            }
            let projectTags = ancestors.map(\.title)
            let combinedTags = Self.dedupe(projectTags + line.inlineTags)
            items.append(ParsedCaptureItem(title: line.title, isDone: line.isDone, tags: combinedTags))
            ancestors.append((depth: entry.depth, title: line.title))
        }

        return items
    }

    private static func depth(forIndent indent: Int, stack: inout [Int]) -> Int {
        while let top = stack.last, indent < top { stack.removeLast() }
        if let top = stack.last, indent == top { return stack.count - 1 }
        stack.append(indent)
        return stack.count - 1
    }

    private static func dedupe(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in tags {
            let key = t.lowercased()
            if !t.isEmpty && !seen.contains(key) {
                seen.insert(key)
                out.append(t)
            }
        }
        return out
    }
}

/// A single parsed source line.
private struct ListLine {
    var indent: Int
    var title: String
    var isDone: Bool
    var hasCheckbox: Bool
    var inlineTags: [String]
    var isList: Bool

    static let nonList = ListLine(indent: -1, title: "", isDone: false, hasCheckbox: false, inlineTags: [], isList: false)

    // Leading whitespace, a bullet (-, *, +) or number (1. / 1) ), then a space.
    private static let marker = try! NSRegularExpression(
        pattern: #"^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$"#
    )
    // Optional leading checkbox: [ ] / [x] / [X]
    private static let checkbox = try! NSRegularExpression(
        pattern: #"^\[([ xX])\]\s+(.*)$"#
    )
    private static let hashtag = try! NSRegularExpression(
        pattern: #"(?:^|\s)#([\p{L}\p{N}][\p{L}\p{N}_-]*)"#
    )

    static func parse(_ raw: String) -> ListLine? {
        let ns = raw as NSString
        guard let m = marker.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let indentStr = ns.substring(with: m.range(at: 1))
        let indent = indentStr.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        var content = ns.substring(with: m.range(at: 2))

        var isDone = false
        var hasCheckbox = false
        let cns = content as NSString
        if let cb = checkbox.firstMatch(in: content, range: NSRange(location: 0, length: cns.length)) {
            hasCheckbox = true
            let mark = (content as NSString).substring(with: cb.range(at: 1))
            isDone = (mark == "x" || mark == "X")
            content = (content as NSString).substring(with: cb.range(at: 2))
        }

        let tags = extractTags(content)
        let title = stripTags(content).trimmingCharacters(in: .whitespaces)
        return ListLine(indent: indent, title: title, isDone: isDone, hasCheckbox: hasCheckbox, inlineTags: tags, isList: true)
    }

    private static func extractTags(_ s: String) -> [String] {
        let ns = s as NSString
        return hashtag.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func stripTags(_ s: String) -> String {
        let ns = s as NSString
        let stripped = hashtag.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: ns.length), withTemplate: ""
        )
        return stripped.replacingOccurrences(of: "  ", with: " ")
    }
}
