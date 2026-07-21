import Foundation
import SwiftUI

enum RelayRichText {
    static func attributed(_ source: String) -> AttributedString {
        let prepared = preparedMarkdown(source)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: prepared, options: options))
            ?? AttributedString(prepared)
    }

    static func plain(_ source: String) -> String {
        String(attributed(source).characters)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func sanitized(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !isInternalDirective($0) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preparedMarkdown(_ source: String) -> String {
        var insideCodeFence = false
        var output: [String] = []

        for rawLine in sanitized(source).split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            var line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                insideCodeFence.toggle()
                continue
            }
            if insideCodeFence {
                output.append(line)
                continue
            }

            line = removingHeadingMarker(from: line)
            line = replacingListMarker(in: line)
            if isTableSeparator(line) { continue }
            line = replacingTablePipes(in: line)
            output.append(line)
        }

        return collapseBlankLines(output).joined(separator: "\n")
    }

    private static func isInternalDirective(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("::"),
            let openingBrace = trimmed.firstIndex(of: "{"),
            trimmed.hasSuffix("}")
        else {
            return false
        }
        let nameStart = trimmed.index(trimmed.startIndex, offsetBy: 2)
        let name = trimmed[nameStart..<openingBrace]
        return !name.isEmpty
            && name.allSatisfy {
                $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
            }
    }

    private static func removingHeadingMarker(from line: String) -> String {
        let indentation = line.prefix(while: { $0 == " " || $0 == "\t" })
        let content = line.dropFirst(indentation.count)
        let hashes = content.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count),
            content.dropFirst(hashes.count).first == " "
        else {
            return line
        }
        return String(indentation + content.dropFirst(hashes.count + 1))
    }

    private static func replacingListMarker(in line: String) -> String {
        let indentation = line.prefix(while: { $0 == " " || $0 == "\t" })
        let content = line.dropFirst(indentation.count)
        guard content.count >= 2 else { return line }
        let marker = content.first
        guard marker == "-" || marker == "*" || marker == "+",
            content.dropFirst().first == " "
        else {
            return line
        }
        return String(indentation) + "• " + content.dropFirst(2)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let content = line.filter { !$0.isWhitespace && $0 != "|" }
        return content.count >= 3
            && content.allSatisfy { $0 == "-" || $0 == ":" }
    }

    private static func replacingTablePipes(in line: String) -> String {
        guard line.contains("|") else { return line }
        return line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
            .replacingOccurrences(of: " | ", with: "  ·  ")
    }

    private static func collapseBlankLines(_ lines: [String]) -> [String] {
        var previousWasBlank = false
        return lines.filter { line in
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            defer { previousWasBlank = isBlank }
            return !isBlank || !previousWasBlank
        }
    }
}

struct RelayRichTextView: View {
    let text: String
    var lineLimit: Int?

    init(_ text: String, lineLimit: Int? = nil) {
        self.text = text
        self.lineLimit = lineLimit
    }

    var body: some View {
        Text(RelayRichText.attributed(text))
            .lineLimit(lineLimit)
            .tint(RelayPalette.accentHighlight)
            .accessibilityLabel(RelayRichText.plain(text))
    }
}
