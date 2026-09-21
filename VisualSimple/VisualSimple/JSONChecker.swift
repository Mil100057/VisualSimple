//
//  JSONChecker.swift
//  VisualSimple
//

import Foundation

/// Strict RFC 8259 parser used only to locate the first error: Foundation's parsers
/// accept trailing commas and other extensions, which is not what a checker should do.
nonisolated enum JSONChecker {
    static func check(_ text: String) -> ValidationResult {
        var parser = Parser(units: Array(text.utf16))
        parser.skipWhitespace()
        guard !parser.atEnd else { return .notApplicable }
        if let issue = parser.parseValue() { return .issue(issue) }
        parser.skipWhitespace()
        if !parser.atEnd {
            return .issue(parser.issue("Unexpected content after the top-level value"))
        }
        return .valid(String(localized: "Valid JSON"))
    }

    private struct Parser {
        let units: [UInt16]
        var i = 0
        var line = 1
        var column = 1

        init(units: [UInt16]) {
            self.units = units
        }

        var atEnd: Bool { i >= units.count }
        var current: UInt16? { atEnd ? nil : units[i] }

        func issue(_ message: String) -> SyntaxIssue {
            SyntaxIssue(message: message, line: line, column: column, utf16Offset: i)
        }

        mutating func advance() {
            guard !atEnd else { return }
            if units[i] == 0x0A {
                line += 1
                column = 1
            } else {
                column += 1
            }
            i += 1
        }

        mutating func skipWhitespace() {
            while let c = current, c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                advance()
            }
        }

        private func describeCurrent() -> String {
            guard let c = current else { return String(localized: "end of file") }
            if c == 0x0A { return String(localized: "line break") }
            return "'\(String(utf16CodeUnits: [c], count: 1))'"
        }

        mutating func parseValue() -> SyntaxIssue? {
            guard let c = current else { return issue(String(localized: "Unexpected end of file, a value was expected")) }
            switch c {
            case 0x7B: return parseObject()
            case 0x5B: return parseArray()
            case 0x22: return parseString()
            case 0x74: return parseLiteral("true")
            case 0x66: return parseLiteral("false")
            case 0x6E: return parseLiteral("null")
            case 0x2D, 0x30...0x39: return parseNumber()
            case 0x27: return issue(String(localized: "Strings must use double quotes"))
            default: return issue(String(localized: "Unexpected \(describeCurrent()), a value was expected"))
            }
        }

        private mutating func parseObject() -> SyntaxIssue? {
            advance()
            skipWhitespace()
            if current == 0x7D {
                advance()
                return nil
            }
            while true {
                skipWhitespace()
                guard current == 0x22 else {
                    if current == 0x7D { return issue(String(localized: "Trailing comma before '}'")) }
                    return issue(String(localized: "Unexpected \(describeCurrent()), a quoted key was expected"))
                }
                if let error = parseString() { return error }
                skipWhitespace()
                guard current == 0x3A else { return issue(String(localized: "Unexpected \(describeCurrent()), ':' was expected after the key")) }
                advance()
                skipWhitespace()
                if let error = parseValue() { return error }
                skipWhitespace()
                if current == 0x2C {
                    advance()
                    continue
                }
                if current == 0x7D {
                    advance()
                    return nil
                }
                return issue(String(localized: "Unexpected \(describeCurrent()), ',' or '}' was expected"))
            }
        }

        private mutating func parseArray() -> SyntaxIssue? {
            advance()
            skipWhitespace()
            if current == 0x5D {
                advance()
                return nil
            }
            while true {
                skipWhitespace()
                if current == 0x5D { return issue(String(localized: "Trailing comma before ']'")) }
                if let error = parseValue() { return error }
                skipWhitespace()
                if current == 0x2C {
                    advance()
                    continue
                }
                if current == 0x5D {
                    advance()
                    return nil
                }
                return issue(String(localized: "Unexpected \(describeCurrent()), ',' or ']' was expected"))
            }
        }

        private mutating func parseString() -> SyntaxIssue? {
            let start = issue(String(localized: "Unterminated string"))
            advance()
            while let c = current {
                switch c {
                case 0x22:
                    advance()
                    return nil
                case 0x5C:
                    advance()
                    guard let escaped = current else { return start }
                    switch escaped {
                    case 0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74:
                        advance()
                    case 0x75:
                        advance()
                        for _ in 0..<4 {
                            guard let h = current, isHexDigit(h) else { return issue(String(localized: "Invalid \\u escape, four hex digits were expected")) }
                            advance()
                        }
                    default:
                        return issue(String(localized: "Invalid escape '\\\(String(utf16CodeUnits: [escaped], count: 1))'"))
                    }
                case 0x0A:
                    return issue(String(localized: "Line break inside a string, use \\n"))
                case 0x00...0x1F:
                    return issue(String(localized: "Control character inside a string"))
                default:
                    advance()
                }
            }
            return start
        }

        private mutating func parseLiteral(_ literal: String) -> SyntaxIssue? {
            let expected = Array(literal.utf16)
            let start = issue(String(localized: "Unexpected \(describeCurrent()), a value was expected"))
            for unit in expected {
                guard current == unit else {
                    return SyntaxIssue(message: String(localized: "Misspelled '\(literal)'"), line: start.line, column: start.column, utf16Offset: start.utf16Offset)
                }
                advance()
            }
            return nil
        }

        private mutating func parseNumber() -> SyntaxIssue? {
            if current == 0x2D { advance() }
            guard let first = current, isDigit(first) else { return issue(String(localized: "A digit was expected after '-'")) }
            if first == 0x30 {
                advance()
                if let c = current, isDigit(c) { return issue(String(localized: "Leading zeros are not allowed")) }
            } else {
                while let c = current, isDigit(c) { advance() }
            }
            if current == 0x2E {
                advance()
                guard let c = current, isDigit(c) else { return issue(String(localized: "A digit was expected after '.'")) }
                while let c = current, isDigit(c) { advance() }
            }
            if current == 0x65 || current == 0x45 {
                advance()
                if current == 0x2B || current == 0x2D { advance() }
                guard let c = current, isDigit(c) else { return issue(String(localized: "A digit was expected in the exponent")) }
                while let c = current, isDigit(c) { advance() }
            }
            return nil
        }

        private func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
        private func isHexDigit(_ c: UInt16) -> Bool {
            isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
        }
    }
}
