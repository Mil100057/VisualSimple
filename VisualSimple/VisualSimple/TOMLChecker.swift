//
//  TOMLChecker.swift
//  VisualSimple
//

import Foundation

/// Partial TOML check: table headers, `key = value` lines, duplicate tables and keys,
/// string termination (including multi-line), arrays spanning lines, inline tables.
nonisolated enum TOMLChecker {
    static func check(_ text: String) -> ValidationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notApplicable }
        var tables: Set<String> = []
        var keys: Set<String> = []          // "table\u{0}key"
        var currentTable = ""
        var keyCount = 0
        var multiline: (quote: Character, line: Int, column: Int, offset: Int)?
        var arrayDepth = 0
        var arrayStart: (line: Int, column: Int, offset: Int)?
        var offset = 0

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let line = String(rawLine)
            defer { offset += rawLine.utf16.count + 1 }

            if let open = multiline {
                if closesMultiline(line, quote: open.quote) { multiline = nil }
                continue
            }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.count
            let body = String(line.dropFirst(indent))
            if body.isEmpty || body.hasPrefix("#") { continue }
            let bodyOffset = offset + indent
            let column = indent + 1

            if arrayDepth > 0 {
                switch scanValue(body, depth: arrayDepth) {
                case .ok(let depth, _):
                    arrayDepth = depth
                    if arrayDepth == 0 { arrayStart = nil }
                case .multilineOpen(let quote, let at):
                    multiline = (quote, lineNumber, column + at, bodyOffset + at)
                case .error(let message, let at):
                    return .issue(SyntaxIssue(message: message, line: lineNumber, column: column + at, utf16Offset: bodyOffset + at))
                }
                continue
            }

            if body.hasPrefix("[") {
                let isArrayTable = body.hasPrefix("[[")
                let closer = isArrayTable ? "]]" : "]"
                guard let end = body.range(of: closer) else {
                    return .issue(SyntaxIssue(message: String(localized: "Table header is not closed with '\(closer)'"), line: lineNumber, column: column, utf16Offset: bodyOffset))
                }
                let name = body[body.index(body.startIndex, offsetBy: isArrayTable ? 2 : 1)..<end.lowerBound].trimmingCharacters(in: .whitespaces)
                if name.isEmpty {
                    return .issue(SyntaxIssue(message: String(localized: "Empty table name"), line: lineNumber, column: column, utf16Offset: bodyOffset))
                }
                let rest = body[end.upperBound...].trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty && !rest.hasPrefix("#") {
                    return .issue(SyntaxIssue(message: String(localized: "Unexpected content after the table header"), line: lineNumber, column: column, utf16Offset: bodyOffset))
                }
                if !isArrayTable && !tables.insert(name).inserted {
                    return .issue(SyntaxIssue(message: String(localized: "Table [\(name)] is defined twice"), line: lineNumber, column: column, utf16Offset: bodyOffset))
                }
                currentTable = name
                if isArrayTable { keys = keys.filter { !$0.hasPrefix(name + "\u{0}") } }
                continue
            }

            guard let equals = keyEnd(in: body) else {
                return .issue(SyntaxIssue(message: String(localized: "'=' expected after the key"), line: lineNumber, column: column, utf16Offset: bodyOffset))
            }
            let key = body[..<equals].trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                return .issue(SyntaxIssue(message: String(localized: "Missing key before '='"), line: lineNumber, column: column, utf16Offset: bodyOffset))
            }
            let fullKey = currentTable + "\u{0}" + key
            if !keys.insert(fullKey).inserted {
                return .issue(SyntaxIssue(message: currentTable.isEmpty ? String(localized: "Duplicate key '\(key)'") : String(localized: "Duplicate key '\(key)' in [\(currentTable)]"), line: lineNumber, column: column, utf16Offset: bodyOffset))
            }
            keyCount += 1

            let valueStart = body.index(after: equals)
            let valueText = String(body[valueStart...])
            let leading = valueText.prefix { $0 == " " || $0 == "\t" }.count
            let value = String(valueText.dropFirst(leading))
            let valueColumnOffset = body.distance(from: body.startIndex, to: valueStart) + leading
            if value.isEmpty || value.hasPrefix("#") {
                return .issue(SyntaxIssue(message: String(localized: "Missing value for '\(key)'"), line: lineNumber, column: column + valueColumnOffset, utf16Offset: bodyOffset + valueColumnOffset))
            }
            switch scanValue(value, depth: 0) {
            case .ok(let depth, let trailing):
                if let trailing {
                    return .issue(SyntaxIssue(message: String(localized: "Unexpected content after the value"), line: lineNumber, column: column + valueColumnOffset + trailing, utf16Offset: bodyOffset + valueColumnOffset + trailing))
                }
                arrayDepth = depth
                if depth > 0 { arrayStart = (lineNumber, column + valueColumnOffset, bodyOffset + valueColumnOffset) }
            case .multilineOpen(let quote, let at):
                multiline = (quote, lineNumber, column + valueColumnOffset + at, bodyOffset + valueColumnOffset + at)
            case .error(let message, let at):
                return .issue(SyntaxIssue(message: message, line: lineNumber, column: column + valueColumnOffset + at, utf16Offset: bodyOffset + valueColumnOffset + at))
            }
        }

        if let multiline {
            return .issue(SyntaxIssue(message: String(localized: "Unterminated multi-line string"), line: multiline.line, column: multiline.column, utf16Offset: multiline.offset))
        }
        if arrayDepth > 0, let arrayStart {
            return .issue(SyntaxIssue(message: String(localized: "Unclosed array"), line: arrayStart.line, column: arrayStart.column, utf16Offset: arrayStart.offset))
        }
        return .valid(String(localized: "TOML, keys: \(keyCount), tables: \(tables.count)"))
    }

    private enum Scan {
        case ok(depth: Int, trailingAt: Int?)
        case multilineOpen(quote: Character, at: Int)
        case error(String, at: Int)
    }

    /// Walks a value (possibly the continuation of an array), tracking [ ] and { }
    /// outside strings. Reports garbage after a complete top-level scalar.
    private static func scanValue(_ text: String, depth start: Int) -> Scan {
        let chars = Array(text)
        var depth = start
        var i = 0
        var sawScalar = false
        while i < chars.count {
            let c = chars[i]
            if c == "#" { break }
            if c == " " || c == "\t" { i += 1; continue }
            if depth == 0 && sawScalar { return .ok(depth: 0, trailingAt: i) }
            if c == "\"" || c == "'" {
                if i + 2 < chars.count, chars[i + 1] == c, chars[i + 2] == c {
                    // Multi-line string: closes on this line or later.
                    let rest = String(chars[(i + 3)...])
                    if let end = closingTriple(in: rest, quote: c) {
                        i += 3 + end + 3
                        sawScalar = depth == 0
                        continue
                    }
                    return .multilineOpen(quote: c, at: i)
                }
                var j = i + 1
                var closed = false
                while j < chars.count {
                    if c == "\"" && chars[j] == "\\" { j += 2; continue }
                    if chars[j] == c { closed = true; break }
                    j += 1
                }
                if !closed { return .error(String(localized: "Unterminated string"), at: i) }
                i = j + 1
                sawScalar = depth == 0
                continue
            }
            if c == "[" || c == "{" { depth += 1; i += 1; continue }
            if c == "]" || c == "}" {
                depth -= 1
                if depth < 0 { return .error(String(localized: "Unexpected '\(String(c))'"), at: i) }
                i += 1
                if depth == 0 { sawScalar = true }
                continue
            }
            if c == "," { i += 1; continue }
            // Bare scalar: number, boolean, date, or a bare key inside an inline table.
            var j = i
            while j < chars.count, chars[j] != "," && chars[j] != "]" && chars[j] != "}" && chars[j] != "#" && chars[j] != " " && chars[j] != "\t" { j += 1 }
            if depth == 0 {
                let scalar = String(chars[i..<j])
                if !isBareScalar(scalar) { return .error(String(localized: "Invalid value '\(scalar)'"), at: i) }
                sawScalar = true
            }
            i = j
        }
        return .ok(depth: depth, trailingAt: nil)
    }

    private static func closingTriple(in text: String, quote: Character) -> Int? {
        let chars = Array(text)
        var i = 0
        while i + 2 < chars.count {
            if quote == "\"" && chars[i] == "\\" { i += 2; continue }
            if chars[i] == quote && chars[i + 1] == quote && chars[i + 2] == quote { return i }
            i += 1
        }
        return nil
    }

    private static func closesMultiline(_ line: String, quote: Character) -> Bool {
        closingTriple(in: line, quote: quote) != nil
    }

    private static func keyEnd(in body: String) -> String.Index? {
        var inQuote: Character?
        var index = body.startIndex
        while index < body.endIndex {
            let c = body[index]
            if let q = inQuote { if c == q { inQuote = nil } }
            else if c == "\"" || c == "'" { inQuote = c }
            else if c == "=" { return index }
            else if c == "#" { return nil }
            index = body.index(after: index)
        }
        return nil
    }

    private static let bareScalar = try! NSRegularExpression(pattern: #"^(true|false|[+-]?(inf|nan)|[+-]?(0x[0-9A-Fa-f_]+|0o[0-7_]+|0b[01_]+|\d[\d_]*(\.\d[\d_]*)?([eE][+-]?\d+)?)|\d{4}-\d\d-\d\d([Tt ]\d\d:\d\d(:\d\d(\.\d+)?)?([Zz]|[+-]\d\d:\d\d)?)?|\d\d:\d\d(:\d\d(\.\d+)?)?)$"#)

    private static func isBareScalar(_ s: String) -> Bool {
        bareScalar.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
}
