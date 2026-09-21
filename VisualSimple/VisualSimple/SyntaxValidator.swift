//
//  SyntaxValidator.swift
//  VisualSimple
//

import Foundation
import JavaScriptCore

/// One problem found in the text. Line and column are 1-based;
/// `utf16Offset` is where the caret should go.
nonisolated struct SyntaxIssue: Equatable {
    let message: String
    let line: Int
    let column: Int
    let utf16Offset: Int

    var summary: String {
        String(localized: "Line \(line), column \(column): \(message)")
    }
}

nonisolated enum ValidationResult: Equatable {
    /// Nothing checks this kind of content.
    case notApplicable
    case valid(String)
    case issue(SyntaxIssue)
}

/// Checks the structure of a document, per language, using system parsers where
/// they are strict enough and small checkers of our own elsewhere.
nonisolated enum SyntaxValidator {
    static func validate(_ text: String, language: SyntaxLanguage, format: SaveFormat, fileExtension: String = "") -> ValidationResult {
        if format == .csv || format == .tsv {
            return CSVChecker.check(text)
        }
        switch fileExtension.lowercased() {
        case "plist", "entitlements":
            return PlistChecker.check(text, xml: checkXML(text))
        case "xcstrings":
            return XCStringsChecker.check(text, json: JSONChecker.check(text))
        default:
            break
        }
        switch language {
        case .json:
            return JSONChecker.check(text)
        case .xml:
            return checkXML(text)
        case .strings:
            return StringsChecker.check(text)
        case .toml:
            return TOMLChecker.check(text)
        case .ini:
            return EnvIniChecker.check(text, isEnv: format == .env || fileExtension.lowercased() == "env" || fileExtension.isEmpty && format == .env)
        case .markdown:
            return MarkdownChecker.check(text)
        case .yaml:
            return YAMLChecker.check(text)
        case .html:
            return HTMLChecker.check(text)
        case .javascript:
            return checkJavaScript(text)
        case .swift:
            return BalanceChecker.check(text, rules: .swift)
        case .css:
            return BalanceChecker.check(text, rules: .css)
        case .python:
            return BalanceChecker.check(text, rules: .python)
        case .typescript:
            return BalanceChecker.check(text, rules: .typescript)
        case .rust:
            return BalanceChecker.check(text, rules: .named("Rust"))
        case .go:
            return BalanceChecker.check(text, rules: .named("Go"))
        case .c:
            return BalanceChecker.check(text, rules: .named("C"))
        case .java:
            return BalanceChecker.check(text, rules: .named("Java"))
        case .kotlin:
            return BalanceChecker.check(text, rules: .named("Kotlin"))
        case .sql:
            return BalanceChecker.check(text, rules: .sql)
        default:
            return .notApplicable
        }
    }

    // MARK: XML

    /// XMLParser knows the column, XMLDocument has readable messages: both are used.
    private static func checkXML(_ text: String) -> ValidationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notApplicable }
        let data = Data(text.utf8)
        let parser = XMLParser(data: data)
        let recorder = XMLErrorRecorder()
        parser.delegate = recorder
        if parser.parse() {
            return .valid(String(localized: "Valid XML"))
        }

        var message = String(localized: "Malformed XML")
        do {
            _ = try XMLDocument(data: data, options: [])
        } catch {
            if let first = error.localizedDescription.split(separator: "\n").first {
                message = String(first).replacingOccurrences(of: #"^Line \d+: "#, with: "", options: .regularExpression)
            }
        }
        let line = max(1, recorder.line)
        let column = max(1, recorder.column)
        return .issue(SyntaxIssue(
            message: message,
            line: line,
            column: column,
            utf16Offset: TextPosition.utf16Offset(line: line, column: column, in: text)
        ))
    }

    private final class XMLErrorRecorder: NSObject, XMLParserDelegate {
        var line = 0
        var column = 0

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
            if line == 0 {
                line = parser.lineNumber
                column = parser.columnNumber
            }
        }
    }

    // MARK: JavaScript

    /// JavaScriptCore parses without running anything.
    private static func checkJavaScript(_ text: String) -> ValidationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notApplicable }
        guard let context = JSContext() else { return .notApplicable }
        let script = JSStringCreateWithCFString(text as CFString)
        defer { JSStringRelease(script) }
        var exception: JSValueRef?
        if JSCheckScriptSyntax(context.jsGlobalContextRef, script, nil, 1, &exception) {
            return .valid(String(localized: "Valid JavaScript"))
        }
        var message = String(localized: "Syntax error")
        var line = 1
        if let exception, let value = JSValue(jsValueRef: exception, in: context) {
            if let text = value.forProperty("message")?.toString(), !text.isEmpty, text != "undefined" {
                message = text
            }
            if let number = value.forProperty("line"), number.isNumber {
                line = max(1, Int(number.toInt32()))
            }
        }
        return .issue(SyntaxIssue(
            message: message,
            line: line,
            column: 1,
            utf16Offset: TextPosition.utf16Offset(line: line, column: 1, in: text)
        ))
    }
}

nonisolated enum TextPosition {
    /// UTF-16 offset of a 1-based line and column (column counted in UTF-16 units).
    static func utf16Offset(line: Int, column: Int, in text: String) -> Int {
        let utf16 = text.utf16
        var currentLine = 1
        var index = utf16.startIndex
        while currentLine < line, index < utf16.endIndex {
            if utf16[index] == 0x0A { currentLine += 1 }
            index = utf16.index(after: index)
        }
        let lineStart = utf16.distance(from: utf16.startIndex, to: index)
        var lineLength = 0
        while index < utf16.endIndex, utf16[index] != 0x0A {
            lineLength += 1
            index = utf16.index(after: index)
        }
        return lineStart + min(max(column - 1, 0), lineLength)
    }
}

// MARK: - CSV

/// RFC 4180 with the delimiter guessed from the first row (comma, semicolon or tab).
nonisolated enum CSVChecker {
    static func check(_ text: String) -> ValidationResult {
        let units = Array(text.utf16)
        guard units.contains(where: { $0 != 0x20 && $0 != 0x0A && $0 != 0x0D && $0 != 0x09 }) else { return .notApplicable }

        let delimiter = guessDelimiter(units)
        var rows: [(line: Int, fields: Int)] = []
        var fields = 1
        var rowLine = 1
        var line = 1
        var column = 1
        var inQuotes = false
        var quoteStartLine = 1
        var quoteStartColumn = 1
        var quoteStartOffset = 0
        var rowHasContent = false
        var i = 0

        func endRow() {
            if rowHasContent || fields > 1 {
                rows.append((rowLine, fields))
            }
            fields = 1
            rowHasContent = false
            rowLine = line + 1
        }

        while i < units.count {
            let unit = units[i]
            if inQuotes {
                if unit == 0x22 {
                    if i + 1 < units.count, units[i + 1] == 0x22 {
                        i += 1
                        column += 1
                    } else {
                        inQuotes = false
                    }
                } else if unit == 0x0A {
                    line += 1
                    column = 0
                }
            } else if unit == 0x22 {
                inQuotes = true
                quoteStartLine = line
                quoteStartColumn = column
                quoteStartOffset = i
                rowHasContent = true
            } else if unit == delimiter {
                fields += 1
                rowHasContent = true
            } else if unit == 0x0A {
                endRow()
                line += 1
                column = 0
            } else if unit != 0x0D {
                rowHasContent = true
            }
            i += 1
            column += 1
        }
        if inQuotes {
            return .issue(SyntaxIssue(
                message: String(localized: "Unterminated quoted field"),
                line: quoteStartLine,
                column: quoteStartColumn,
                utf16Offset: quoteStartOffset
            ))
        }
        endRow()

        guard let first = rows.first else { return .notApplicable }
        for row in rows.dropFirst() where row.fields != first.fields {
            return .issue(SyntaxIssue(
                message: String(localized: "Fields: \(row.fields), the first row has \(first.fields)"),
                line: row.line,
                column: 1,
                utf16Offset: TextPosition.utf16Offset(line: row.line, column: 1, in: text)
            ))
        }
        let name: String
        switch delimiter {
        case 0x3B: name = String(localized: "semicolon")
        case 0x09: name = String(localized: "tab")
        default: name = String(localized: "comma")
        }
        return .valid(String(localized: "CSV, rows: \(rows.count), fields: \(first.fields), separator: \(name)"))
    }

    private static func guessDelimiter(_ units: [UInt16]) -> UInt16 {
        var counts: [UInt16: Int] = [0x2C: 0, 0x3B: 0, 0x09: 0]
        var inQuotes = false
        for unit in units {
            if unit == 0x22 { inQuotes.toggle() }
            if unit == 0x0A, !inQuotes { break }
            if !inQuotes, counts[unit] != nil { counts[unit, default: 0] += 1 }
        }
        let best = counts.max { $0.value < $1.value }
        return (best?.value ?? 0) > 0 ? best!.key : 0x2C
    }
}

// MARK: - Brackets and strings

/// Pairs (), [] and {} and checks string and comment termination, skipping
/// whatever sits inside strings and comments. Language quirks come from the rules.
nonisolated enum BalanceChecker {
    struct Rules {
        var lineComments: [String]
        var blockComment: (open: String, close: String)?
        var nestedBlockComments: Bool
        var stringDelimiters: [UInt16]
        var tripleQuotes: Bool
        var swiftInterpolation: Bool
        var label: String

        static let swift = Rules(
            lineComments: ["//"], blockComment: ("/*", "*/"), nestedBlockComments: true,
            stringDelimiters: [0x22], tripleQuotes: true, swiftInterpolation: true, label: "Swift"
        )
        static let css = Rules(
            lineComments: [], blockComment: ("/*", "*/"), nestedBlockComments: false,
            stringDelimiters: [0x22, 0x27], tripleQuotes: false, swiftInterpolation: false, label: "CSS"
        )
        static let typescript = Rules(
            lineComments: ["//"], blockComment: ("/*", "*/"), nestedBlockComments: false,
            stringDelimiters: [0x22, 0x27, 0x60], tripleQuotes: false, swiftInterpolation: false, label: "TypeScript"
        )
        static let sql = Rules(
            lineComments: ["--"], blockComment: ("/*", "*/"), nestedBlockComments: false,
            stringDelimiters: [0x27], tripleQuotes: false, swiftInterpolation: false, label: "SQL"
        )
        /// C-family defaults: // and /* */ comments, "..." and '...' strings.
        static func named(_ label: String) -> Rules {
            Rules(
                lineComments: ["//"], blockComment: ("/*", "*/"), nestedBlockComments: false,
                stringDelimiters: [0x22, 0x27], tripleQuotes: false, swiftInterpolation: false, label: label
            )
        }
        static let python = Rules(
            lineComments: ["#"], blockComment: nil, nestedBlockComments: false,
            stringDelimiters: [0x22, 0x27], tripleQuotes: true, swiftInterpolation: false, label: "Python"
        )
    }

    private struct Open {
        let unit: UInt16
        let line: Int
        let column: Int
        let offset: Int
    }

    static func check(_ text: String, rules: Rules) -> ValidationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notApplicable }
        var scanner = Scanner(units: Array(text.utf16), rules: rules)
        if let issue = scanner.run() {
            return .issue(issue)
        }
        return .valid(String(localized: "\(rules.label): brackets and strings balanced"))
    }

    private struct Scanner {
        let units: [UInt16]
        let rules: Rules
        var i = 0
        var line = 1
        var column = 1
        var stack: [Open] = []

        init(units: [UInt16], rules: Rules) {
            self.units = units
            self.rules = rules
        }

        private static let pairs: [UInt16: UInt16] = [0x29: 0x28, 0x5D: 0x5B, 0x7D: 0x7B] // ) ] }
        private static let openers: Set<UInt16> = [0x28, 0x5B, 0x7B]

        mutating func run() -> SyntaxIssue? {
            while i < units.count {
                if let issue = step() { return issue }
            }
            if let last = stack.last {
                return SyntaxIssue(
                    message: String(localized: "Unclosed '\(name(last.unit))'"),
                    line: last.line, column: last.column, utf16Offset: last.offset
                )
            }
            return nil
        }

        /// Handles one token starting at `i`; returns an issue or nil.
        private mutating func step() -> SyntaxIssue? {
            let unit = units[i]

            if let block = rules.blockComment, matches(block.open) {
                return skipBlockComment(block)
            }
            for marker in rules.lineComments where matches(marker) {
                skipToEndOfLine()
                return nil
            }
            if rules.stringDelimiters.contains(unit) {
                return skipString(delimiter: unit)
            }
            if Self.openers.contains(unit) {
                stack.append(Open(unit: unit, line: line, column: column, offset: i))
            } else if let opener = Self.pairs[unit] {
                guard let last = stack.popLast() else {
                    return SyntaxIssue(message: String(localized: "Unexpected '\(name(unit))'"), line: line, column: column, utf16Offset: i)
                }
                if last.unit != opener {
                    return SyntaxIssue(
                        message: String(localized: "Expected '\(name(closer(for: last.unit)))' to close '\(name(last.unit))' from line \(last.line), found '\(name(unit))'"),
                        line: line, column: column, utf16Offset: i
                    )
                }
            }
            advance()
            return nil
        }

        private mutating func skipBlockComment(_ block: (open: String, close: String)) -> SyntaxIssue? {
            let startLine = line, startColumn = column, startOffset = i
            var depth = 0
            repeat {
                if matches(block.open) {
                    depth += 1
                    advance(by: block.open.utf16.count)
                    if !rules.nestedBlockComments { depth = 1 }
                } else if matches(block.close) {
                    depth -= 1
                    advance(by: block.close.utf16.count)
                } else {
                    advance()
                }
            } while depth > 0 && i < units.count
            if depth > 0 {
                return SyntaxIssue(message: String(localized: "Unterminated comment"), line: startLine, column: startColumn, utf16Offset: startOffset)
            }
            return nil
        }

        private mutating func skipString(delimiter: UInt16) -> SyntaxIssue? {
            let startLine = line, startColumn = column, startOffset = i
            let triple = rules.tripleQuotes && i + 2 < units.count && units[i + 1] == delimiter && units[i + 2] == delimiter
            advance(by: triple ? 3 : 1)
            while i < units.count {
                let unit = units[i]
                if unit == 0x5C { // backslash
                    if rules.swiftInterpolation, i + 1 < units.count, units[i + 1] == 0x28 {
                        advance(by: 2)
                        if let issue = skipInterpolation() { return issue }
                        continue
                    }
                    advance(by: 2)
                    continue
                }
                if unit == delimiter {
                    if !triple {
                        advance()
                        return nil
                    }
                    if i + 2 < units.count, units[i + 1] == delimiter, units[i + 2] == delimiter {
                        advance(by: 3)
                        return nil
                    }
                } else if unit == 0x0A, !triple {
                    return SyntaxIssue(message: String(localized: "Unterminated string"), line: startLine, column: startColumn, utf16Offset: startOffset)
                }
                advance()
            }
            return SyntaxIssue(
                message: triple ? "Unterminated multi-line string" : "Unterminated string",
                line: startLine, column: startColumn, utf16Offset: startOffset
            )
        }

        /// Inside `\( ... )`: balance parentheses, and nested strings are strings again.
        private mutating func skipInterpolation() -> SyntaxIssue? {
            var depth = 1
            while i < units.count, depth > 0 {
                let unit = units[i]
                if rules.stringDelimiters.contains(unit) {
                    if let issue = skipString(delimiter: unit) { return issue }
                    continue
                }
                if unit == 0x28 { depth += 1 }
                if unit == 0x29 { depth -= 1 }
                advance()
            }
            return nil
        }

        private func matches(_ marker: String) -> Bool {
            let m = Array(marker.utf16)
            guard i + m.count <= units.count else { return false }
            return Array(units[i..<i + m.count]) == m
        }

        private mutating func skipToEndOfLine() {
            while i < units.count, units[i] != 0x0A { advance() }
        }

        private mutating func advance(by count: Int = 1) {
            for _ in 0..<count where i < units.count {
                if units[i] == 0x0A {
                    line += 1
                    column = 1
                } else {
                    column += 1
                }
                i += 1
            }
        }

        private func closer(for opener: UInt16) -> UInt16 {
            switch opener {
            case 0x28: 0x29
            case 0x5B: 0x5D
            default: 0x7D
            }
        }

        private func name(_ unit: UInt16) -> String {
            String(utf16CodeUnits: [unit], count: 1)
        }
    }
}
