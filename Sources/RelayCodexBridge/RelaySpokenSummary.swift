import Foundation

/// Turns a controller answer into a short, speech-friendly summary.
///
/// Relay's answers are written for the eye — occasionally with markdown
/// bullets, code spans, or several sentences. Reading that verbatim is
/// grating, so when Relay answers a *spoken* request it speaks only a
/// concise lead: the answer stripped of markdown and capped to its first
/// sentence or two. The controller already leads with the gist ("Lead
/// with the useful answer, current status, or action"), so the lead
/// sentences carry the point.
///
/// This is deliberately a single pure seam. If the controller later emits
/// a dedicated spoken field, only this type needs to change.
public enum RelaySpokenSummary {
    /// Upper bound on spoken characters — roughly one or two short
    /// sentences. Long enough to carry the gist, short enough to stay a
    /// summary rather than a monologue.
    public static let characterLimit = 240

    public static func make(from answer: String) -> String {
        let plain = plainText(from: answer)
        guard !plain.isEmpty else { return "" }

        let sentences = sentences(in: plain)
        guard !sentences.isEmpty else {
            return truncated(plain)
        }

        var spoken = ""
        for sentence in sentences {
            if spoken.isEmpty {
                spoken = sentence
            } else if spoken.count + 1 + sentence.count <= characterLimit {
                spoken += " " + sentence
            } else {
                break
            }
        }
        return truncated(spoken)
    }

    // MARK: - Markdown → plain text

    private static func plainText(from answer: String) -> String {
        var inFencedCode = false
        var lines: [String] = []

        for rawLine in answer.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        ) {
            let line = rawLine.trimmingCharacters(
                in: .whitespaces
            )
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFencedCode.toggle()
                continue
            }
            if inFencedCode { continue }

            let cleaned = strippedInlineMarkup(
                strippedBlockPrefix(line)
            )
            if !cleaned.isEmpty {
                lines.append(cleaned)
            }
        }

        return collapseWhitespace(lines.joined(separator: " "))
    }

    /// Removes leading block markers — headings, blockquotes, and list
    /// bullets — that would otherwise be read aloud as stray symbols.
    private static func strippedBlockPrefix(_ line: String) -> String {
        var result = line

        while true {
            let trimmed = result.trimmingCharacters(in: .whitespaces)
            if trimmed != result {
                result = trimmed
            }

            if result.hasPrefix("#") {
                result = String(result.drop(while: { $0 == "#" }))
                continue
            }
            if result.hasPrefix(">") {
                result.removeFirst()
                continue
            }
            if let first = result.first,
               "-*+".contains(first),
               result.dropFirst().first == " " {
                result.removeFirst()
                continue
            }
            if let orderedPrefix = orderedListPrefixLength(of: result) {
                result.removeFirst(orderedPrefix)
                continue
            }
            break
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Length of a leading ordered-list marker such as `12.` or `3)`,
    /// or `nil` when the line does not start with one.
    private static func orderedListPrefixLength(
        of line: String
    ) -> Int? {
        var digits = 0
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            digits += 1
            index = line.index(after: index)
        }
        guard digits > 0, index < line.endIndex,
              line[index] == "." || line[index] == ")" else {
            return nil
        }
        let afterDelimiter = line.index(after: index)
        guard afterDelimiter < line.endIndex,
              line[afterDelimiter] == " " else {
            return nil
        }
        return digits + 1
    }

    private static let emphasisCharacters: Set<Character> = [
        "*", "`", "~",
    ]

    /// Strips inline markup: link/image syntax becomes its visible text,
    /// and emphasis/code markers are removed.
    private static func strippedInlineMarkup(_ text: String) -> String {
        var result = replacingLinks(text)
        result.removeAll(where: emphasisCharacters.contains)
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func replacingLinks(_ text: String) -> String {
        guard text.contains("[") else { return text }
        guard
            let image = try? Regex(#"!\[([^\]]*)\]\([^)]*\)"#),
            let link = try? Regex(#"\[([^\]]*)\]\([^)]*\)"#)
        else {
            return text
        }
        let withoutImages = text.replacing(image) { match in
            match.output[1].substring.map(String.init) ?? ""
        }
        return withoutImages.replacing(link) { match in
            match.output[1].substring.map(String.init) ?? ""
        }
    }

    // MARK: - Sentence handling

    private static func sentences(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: .bySentences
        ) { substring, _, _, _ in
            guard let sentence = substring?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !sentence.isEmpty else {
                return
            }
            result.append(sentence)
        }
        return result
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > characterLimit else { return text }
        let clipped = text.prefix(characterLimit)
        if let lastSpace = clipped.lastIndex(of: " ") {
            return String(clipped[..<lastSpace])
                .trimmingCharacters(in: .whitespaces)
        }
        return String(clipped)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
    }
}
