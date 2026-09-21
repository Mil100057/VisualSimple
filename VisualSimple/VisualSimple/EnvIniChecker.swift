//
//  EnvIniChecker.swift
//  VisualSimple
//

import Foundation

/// `.env` and `.ini` files: every non-comment line is `key=value` (or a `[section]` for INI),
/// keys are unique within their section, quoted values are closed.
nonisolated enum EnvIniChecker {
    static func check(_ text: String, isEnv: Bool) -> ValidationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notApplicable }
        var keys: Set<String> = []
        var section = ""
        var sections = 0
        var count = 0
        var offset = 0

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let line = String(rawLine)
            defer { offset += rawLine.utf16.count + 1 }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.count
            var body = String(line.dropFirst(indent))
            let bodyOffset = offset + indent
            let column = indent + 1
            if body.isEmpty || body.hasPrefix("#") || body.hasPrefix(";") { continue }

            if body.hasPrefix("[") {
                if isEnv {
                    return .issue(SyntaxIssue(message: String(localized: "Sections are not allowed in a .env file"), line: lineNumber, column: column, utf16Offset: bodyOffset))
                }
                guard let end = body.firstIndex(of: "]") else {
                    return .issue(SyntaxIssue(message: String(localized: "Section header is not closed with ']'"), line: lineNumber, column: column, utf16Offset: bodyOffset))
                }
                section = String(body[body.index(after: body.startIndex)..<end]).trimmingCharacters(in: .whitespaces)
                if section.isEmpty {
                    return .issue(SyntaxIssue(message: String(localized: "Empty section name"), line: lineNumber, column: column, utf16Offset: bodyOffset))
                }
                sections += 1
                continue
            }

            var keyOffset = 0
            if isEnv, body.hasPrefix("export ") {
                body = String(body.dropFirst(7))
                keyOffset = 7
            }
            guard let equals = body.firstIndex(where: { $0 == "=" || (!isEnv && $0 == ":") }) else {
                return .issue(SyntaxIssue(message: String(localized: "'=' expected: a line must be key=value"), line: lineNumber, column: column, utf16Offset: bodyOffset))
            }
            let key = body[..<equals].trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                return .issue(SyntaxIssue(message: String(localized: "Missing key before '='"), line: lineNumber, column: column, utf16Offset: bodyOffset))
            }
            if isEnv, key.contains(" ") || key.first!.isNumber {
                return .issue(SyntaxIssue(message: String(localized: "Invalid variable name '\(key)'"), line: lineNumber, column: column + keyOffset, utf16Offset: bodyOffset + keyOffset))
            }
            let fullKey = section + "\u{0}" + (isEnv ? key : key.lowercased())
            if !keys.insert(fullKey).inserted {
                return .issue(SyntaxIssue(message: section.isEmpty ? String(localized: "Duplicate key '\(key)'") : String(localized: "Duplicate key '\(key)' in [\(section)]"), line: lineNumber, column: column + keyOffset, utf16Offset: bodyOffset + keyOffset))
            }
            count += 1

            let value = body[body.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let first = value.first, first == "\"" || first == "'" {
                let rest = value.dropFirst()
                var closed = false
                var escaped = false
                for c in rest {
                    if escaped { escaped = false; continue }
                    if c == "\\" && first == "\"" { escaped = true; continue }
                    if c == first { closed = true; break }
                }
                if !closed {
                    let valueColumn = body.distance(from: body.startIndex, to: equals) + 1 + (body[body.index(after: equals)...].prefix { $0 == " " }.count)
                    return .issue(SyntaxIssue(message: String(localized: "Unterminated quoted value for '\(key)'"), line: lineNumber, column: column + keyOffset + valueColumn, utf16Offset: bodyOffset + keyOffset + valueColumn))
                }
            }
        }
        if isEnv {
            return .valid(String(localized: ".env, variables: \(count)"))
        }
        return .valid(String(localized: "INI, keys: \(count), sections: \(sections)"))
    }
}
