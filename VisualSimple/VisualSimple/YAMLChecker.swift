//
//  YAMLChecker.swift
//  VisualSimple
//

import Foundation

/// Partial YAML check, without a real parser: tabs in indentation, dedents that match
/// no open level, duplicate keys in one mapping, a second `: ` in a plain value,
/// unterminated quoted scalars and unbalanced flow brackets. Anything it does not
/// understand is left alone, so a clean report means "no obvious problem".
nonisolated enum YAMLChecker {
    private struct Line {
        let number: Int
        let indent: Int
        let text: String        // without indentation
        let utf16Start: Int     // offset of the first non-space character
    }

    static func check(_ text: String) -> ValidationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notApplicable }

        var lines: [Line] = []
        var offset = 0
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            var indent = 0
            for scalar in raw.unicodeScalars {
                if scalar == " " { indent += 1 } else if scalar == "\t" {
                    return .issue(SyntaxIssue(message: String(localized: "Tabs are not allowed in indentation"), line: lineNumber, column: indent + 1, utf16Offset: offset + indent))
                } else { break }
            }
            let content = String(raw.dropFirst(indent))
            lines.append(Line(number: lineNumber, indent: indent, text: content, utf16Start: offset + indent))
            offset += raw.utf16.count + 1
        }

        var levels: [Int] = []                      // open block indents
        var keysByIndent: [Int: Set<String>] = [:]  // keys seen per mapping level
        var blockScalarIndent: Int?                 // inside `|` or `>`, content deeper than this
        var quote: (unit: Character, line: Int, column: Int, offset: Int)?
        var flowDepth = 0
        var flowStart: (line: Int, column: Int, offset: Int)?

        for line in lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)

            if let openQuote = quote {
                // Continuation of a multi-line quoted scalar.
                if closesQuote(line.text, quote: openQuote.unit) { quote = nil }
                continue
            }
            if let scalarIndent = blockScalarIndent {
                if trimmed.isEmpty || line.indent > scalarIndent { continue }
                blockScalarIndent = nil
            }
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "---" || trimmed == "..." || trimmed.hasPrefix("%") { continue }

            if flowDepth > 0 {
                let (depth, badClose) = scanFlow(line.text, depth: flowDepth)
                if let badClose {
                    return .issue(SyntaxIssue(message: String(localized: "Unexpected '\(String(badClose.character))'"), line: line.number, column: line.indent + badClose.column, utf16Offset: line.utf16Start + badClose.column - 1))
                }
                flowDepth = depth
                if flowDepth == 0 { flowStart = nil }
                continue
            }

            // Indentation: a dedent must land exactly on a level that is still open.
            var dedented = false
            while let last = levels.last, line.indent < last {
                levels.removeLast()
                keysByIndent[last] = nil
                dedented = true
            }
            if dedented, line.indent != levels.last {
                return .issue(SyntaxIssue(message: String(localized: "Indentation does not match any open block"), line: line.number, column: line.indent + 1, utf16Offset: line.utf16Start))
            }
            if let last = levels.last, line.indent > last, !continuesPreviousValue(lines, before: line) {
                levels.append(line.indent)
            } else if levels.isEmpty {
                levels.append(line.indent)
            } else if let last = levels.last, line.indent != last, !continuesPreviousValue(lines, before: line) {
                return .issue(SyntaxIssue(message: String(localized: "Indentation does not match any open block"), line: line.number, column: line.indent + 1, utf16Offset: line.utf16Start))
            }

            var body = line.text
            var bodyOffset = 0
            // Sequence items: check the content after "- " as if it were its own line.
            while body.hasPrefix("- ") || body == "-" {
                body = String(body.dropFirst(2))
                bodyOffset += 2
                let extra = body.prefix { $0 == " " }.count
                body = String(body.dropFirst(extra))
                bodyOffset += extra
            }
            if body.isEmpty { continue }

            let first = body.first!
            if first == "[" || first == "{" {
                flowStart = (line.number, line.indent + bodyOffset + 1, line.utf16Start + bodyOffset)
                let (depth, badClose) = scanFlow(body, depth: 0)
                if let badClose {
                    return .issue(SyntaxIssue(message: String(localized: "Unexpected '\(String(badClose.character))'"), line: line.number, column: line.indent + bodyOffset + badClose.column, utf16Offset: line.utf16Start + bodyOffset + badClose.column - 1))
                }
                flowDepth = depth
                if flowDepth == 0 { flowStart = nil }
                continue
            }

            if first == "\"" || first == "'" {
                if !closesQuote(String(body.dropFirst()), quote: first) {
                    quote = (first, line.number, line.indent + bodyOffset + 1, line.utf16Start + bodyOffset)
                }
                continue
            }

            // `key: value`
            if let keyRange = keyRange(in: body) {
                let key = String(body[keyRange]).trimmingCharacters(in: .whitespaces)
                let mappingIndent = line.indent + bodyOffset
                if keysByIndent[mappingIndent, default: []].contains(key) {
                    return .issue(SyntaxIssue(message: String(localized: "Duplicate key '\(key)'"), line: line.number, column: mappingIndent + 1, utf16Offset: line.utf16Start + bodyOffset))
                }
                keysByIndent[mappingIndent, default: []].insert(key)
                if bodyOffset > 0, !levels.contains(mappingIndent) { levels.append(mappingIndent) }

                var value = String(body[keyRange.upperBound...].dropFirst()) // after ':'
                let valueOffset = bodyOffset + body.distance(from: body.startIndex, to: keyRange.upperBound) + 1
                let leading = value.prefix { $0 == " " }.count
                value = String(value.dropFirst(leading))
                if value.isEmpty || value.hasPrefix("#") { continue }
                let valueFirst = value.first!
                if valueFirst == "|" || valueFirst == ">" {
                    blockScalarIndent = line.indent
                    continue
                }
                if valueFirst == "[" || valueFirst == "{" {
                    flowStart = (line.number, line.indent + valueOffset + leading + 1, line.utf16Start + valueOffset + leading)
                    let (depth, badClose) = scanFlow(value, depth: 0)
                    if let badClose {
                        return .issue(SyntaxIssue(message: String(localized: "Unexpected '\(String(badClose.character))'"), line: line.number, column: line.indent + valueOffset + leading + badClose.column, utf16Offset: line.utf16Start + valueOffset + leading + badClose.column - 1))
                    }
                    flowDepth = depth
                    if flowDepth == 0 { flowStart = nil }
                    continue
                }
                if valueFirst == "\"" || valueFirst == "'" {
                    if !closesQuote(String(value.dropFirst()), quote: valueFirst) {
                        quote = (valueFirst, line.number, line.indent + valueOffset + leading + 1, line.utf16Start + valueOffset + leading)
                    }
                    continue
                }
                if valueFirst != "&" && valueFirst != "*" && valueFirst != "!" {
                    if let extra = plainValueColon(value) {
                        let column = line.indent + valueOffset + leading + extra + 1
                        return .issue(SyntaxIssue(message: String(localized: "A plain value cannot contain ': ' (quote it)"), line: line.number, column: column, utf16Offset: line.utf16Start + valueOffset + leading + extra))
                    }
                }
            }
        }

        if let quote {
            return .issue(SyntaxIssue(message: String(localized: "Unterminated quoted value"), line: quote.line, column: quote.column, utf16Offset: quote.offset))
        }
        if flowDepth > 0, let flowStart {
            return .issue(SyntaxIssue(message: String(localized: "Unclosed flow collection"), line: flowStart.line, column: flowStart.column, utf16Offset: flowStart.offset))
        }
        return .valid(String(localized: "YAML: indentation, keys, quotes and brackets look fine"))
    }

    /// A deeper line right after `key: value` or `- value` is a plain multi-line scalar, which is legal.
    private static func continuesPreviousValue(_ lines: [Line], before line: Line) -> Bool {
        guard let previous = lines.last(where: { $0.number < line.number && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }),
              line.indent > previous.indent else { return false }
        let trimmed = previous.text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(":") || trimmed.hasSuffix("-") || trimmed.hasPrefix("#") { return false }
        if let range = keyRange(in: trimmed) {
            let value = trimmed[range.upperBound...].dropFirst().trimmingCharacters(in: .whitespaces)
            return !value.isEmpty && !value.hasPrefix("#") && value != "|" && value != ">"
        }
        return true
    }

    /// Range of the key in `key: value` (key ends before the first `: ` or a trailing `:`).
    private static func keyRange(in body: String) -> Range<String.Index>? {
        var inSingle = false, inDouble = false
        var index = body.startIndex
        while index < body.endIndex {
            let c = body[index]
            if c == "'" && !inDouble { inSingle.toggle() }
            else if c == "\"" && !inSingle { inDouble.toggle() }
            else if c == "#" && !inSingle && !inDouble && (index == body.startIndex || body[body.index(before: index)] == " ") { return nil }
            else if c == ":" && !inSingle && !inDouble {
                let next = body.index(after: index)
                if next == body.endIndex || body[next] == " " {
                    return index > body.startIndex ? body.startIndex..<index : nil
                }
            }
            index = body.index(after: index)
        }
        return nil
    }

    /// Offset of a `: ` inside a plain scalar, ignoring a trailing comment.
    private static func plainValueColon(_ value: String) -> Int? {
        var offset = 0
        var previous: Character = " "
        var index = value.startIndex
        while index < value.endIndex {
            let c = value[index]
            if c == "#" && previous == " " { return nil }
            if c == ":" {
                let next = value.index(after: index)
                if next == value.endIndex || value[next] == " " { return offset }
            }
            previous = c
            offset += 1
            index = value.index(after: index)
        }
        return nil
    }

    /// Whether the rest of a quoted scalar closes on this text.
    private static func closesQuote(_ rest: String, quote: Character) -> Bool {
        var index = rest.startIndex
        while index < rest.endIndex {
            let c = rest[index]
            if quote == "\"" && c == "\\" {
                index = rest.index(after: index)
                if index == rest.endIndex { return false }
            } else if c == quote {
                let next = rest.index(after: index)
                if quote == "'" && next < rest.endIndex && rest[next] == "'" {
                    index = next
                } else {
                    return true
                }
            }
            index = rest.index(after: index)
        }
        return false
    }

    /// Tracks [ ] and { } outside quotes. Returns the depth after the text, or the
    /// 1-based column of a closer that has no opener.
    private static func scanFlow(_ text: String, depth start: Int) -> (Int, (character: Character, column: Int)?) {
        var depth = start
        var inSingle = false, inDouble = false
        var column = 0
        var previous: Character = " "
        for c in text {
            column += 1
            if c == "'" && !inDouble { inSingle.toggle() }
            else if c == "\"" && !inSingle { inDouble.toggle() }
            else if !inSingle && !inDouble {
                if c == "#" && previous == " " { break }
                if c == "[" || c == "{" { depth += 1 }
                if c == "]" || c == "}" {
                    depth -= 1
                    if depth < 0 { return (0, (c, column)) }
                }
            }
            previous = c
        }
        return (depth, nil)
    }
}
