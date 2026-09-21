//
//  MarkdownChecker.swift
//  VisualSimple
//

import Foundation

/// Markdown: code fences closed, links and wikilinks closed and not empty,
/// heading levels without jumps, no empty heading. Links to other files are not
/// checked: the sandbox only grants access to the opened file.
nonisolated enum MarkdownChecker {
    static func check(_ text: String) -> ValidationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notApplicable }
        var fence: (marker: String, line: Int, column: Int, offset: Int)?
        var previousHeading = 0
        var headings = 0
        var links = 0
        var offset = 0

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let line = String(rawLine)
            defer { offset += rawLine.utf16.count + 1 }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let open = fence {
                if trimmed.hasPrefix(open.marker), trimmed.trimmingCharacters(in: CharacterSet(charactersIn: String(open.marker.first!))).isEmpty {
                    fence = nil
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix { $0 == trimmed.first! })
                fence = (marker, lineNumber, line.prefix { $0 == " " }.count + 1, offset + line.prefix { $0 == " " }.count)
                continue
            }

            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                if level <= 6 {
                    let title = trimmed.dropFirst(level)
                    if title.isEmpty || (title.first == " " && title.trimmingCharacters(in: .whitespaces).isEmpty) {
                        return .issue(SyntaxIssue(message: String(localized: "Empty heading"), line: lineNumber, column: 1, utf16Offset: offset))
                    }
                    if title.first == " " {
                        if previousHeading > 0, level > previousHeading + 1 {
                            return .issue(SyntaxIssue(message: String(localized: "Heading level jumps from \(previousHeading) to \(level)"), line: lineNumber, column: 1, utf16Offset: offset))
                        }
                        previousHeading = level
                        headings += 1
                    }
                }
            }

            // Wikilinks and Markdown links, scanned outside inline code.
            let units = Array(line.utf16)
            var i = 0
            var inCode = false
            while i < units.count {
                let c = units[i]
                if c == 0x60 { inCode.toggle(); i += 1; continue } // backtick
                if inCode { i += 1; continue }
                if c == 0x5B, i + 1 < units.count, units[i + 1] == 0x5B { // [[
                    guard let close = find("]]", in: units, from: i + 2) else {
                        return .issue(SyntaxIssue(message: String(localized: "Unclosed [[wikilink]]"), line: lineNumber, column: i + 1, utf16Offset: offset + i))
                    }
                    if close == i + 2 {
                        return .issue(SyntaxIssue(message: String(localized: "Empty wikilink"), line: lineNumber, column: i + 1, utf16Offset: offset + i))
                    }
                    links += 1
                    i = close + 2
                    continue
                }
                if c == 0x5B { // [text](target)
                    guard let closeBracket = find("]", in: units, from: i + 1) else { i += 1; continue }
                    if closeBracket + 1 < units.count, units[closeBracket + 1] == 0x28 {
                        guard let closeParen = find(")", in: units, from: closeBracket + 2) else {
                            return .issue(SyntaxIssue(message: String(localized: "Unclosed link: missing ')'"), line: lineNumber, column: i + 1, utf16Offset: offset + i))
                        }
                        let target = units[(closeBracket + 2)..<closeParen]
                        if target.allSatisfy({ $0 == 0x20 }) {
                            return .issue(SyntaxIssue(message: String(localized: "Empty link target"), line: lineNumber, column: i + 1, utf16Offset: offset + i))
                        }
                        links += 1
                        i = closeParen + 1
                        continue
                    }
                    i = closeBracket + 1
                    continue
                }
                i += 1
            }
            if inCode {
                return .issue(SyntaxIssue(message: String(localized: "Unbalanced backticks"), line: lineNumber, column: 1, utf16Offset: offset))
            }
        }
        if let fence {
            return .issue(SyntaxIssue(message: String(localized: "Unclosed code fence"), line: fence.line, column: fence.column, utf16Offset: fence.offset))
        }
        return .valid(String(localized: "Markdown, headings: \(headings), links: \(links), fences closed"))
    }

    private static func find(_ needle: String, in units: [UInt16], from start: Int) -> Int? {
        let n = Array(needle.utf16)
        var i = start
        while i + n.count <= units.count {
            if Array(units[i..<i + n.count]) == n { return i }
            i += 1
        }
        return nil
    }
}
