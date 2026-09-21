//
//  FormatCheckers.swift
//  VisualSimple
//

import Foundation

/// Property lists: well-formed XML first, then Foundation's plist reader for the structure.
nonisolated enum PlistChecker {
    static func check(_ text: String, xml: ValidationResult) -> ValidationResult {
        guard case .valid = xml else { return xml }
        do {
            let object = try PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil)
            if let dictionary = object as? [String: Any] {
                return .valid(String(localized: "Valid property list, dictionary keys: \(dictionary.count)"))
            }
            if let array = object as? [Any] {
                return .valid(String(localized: "Valid property list, array items: \(array.count)"))
            }
            return .valid(String(localized: "Valid property list"))
        } catch {
            let description = (error as NSError).userInfo["NSDebugDescription"] as? String ?? error.localizedDescription
            var line = 1
            if let match = description.range(of: #"line (\d+)"#, options: .regularExpression),
               let number = Int(description[match].split(separator: " ").last ?? "") {
                line = number
            }
            let message = description.replacingOccurrences(of: #"\s*(on|at) line \d+\.?$"#, with: "", options: .regularExpression)
            return .issue(SyntaxIssue(
                message: message.isEmpty ? "Invalid property list" : message,
                line: line,
                column: 1,
                utf16Offset: TextPosition.utf16Offset(line: line, column: 1, in: text)
            ))
        }
    }
}

/// Apple .strings files: `"key" = "value";` entries, C comments, no duplicate keys.
nonisolated enum StringsChecker {
    static func check(_ text: String) -> ValidationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notApplicable }
        let units = Array(text.utf16)
        var i = 0
        var line = 1
        var column = 1
        var keys: Set<String> = []
        var count = 0

        func issue(_ message: String) -> ValidationResult {
            .issue(SyntaxIssue(message: message, line: line, column: column, utf16Offset: i))
        }
        func advance() {
            if units[i] == 0x0A { line += 1; column = 1 } else { column += 1 }
            i += 1
        }
        func skipTrivia() -> ValidationResult? {
            while i < units.count {
                let c = units[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { advance(); continue }
                if c == 0x2F, i + 1 < units.count, units[i + 1] == 0x2F {
                    while i < units.count, units[i] != 0x0A { advance() }
                    continue
                }
                if c == 0x2F, i + 1 < units.count, units[i + 1] == 0x2A {
                    let start = (line, column, i)
                    advance(); advance()
                    var closed = false
                    while i < units.count {
                        if units[i] == 0x2A, i + 1 < units.count, units[i + 1] == 0x2F { advance(); advance(); closed = true; break }
                        advance()
                    }
                    if !closed { return .issue(SyntaxIssue(message: String(localized: "Unterminated comment"), line: start.0, column: start.1, utf16Offset: start.2)) }
                    continue
                }
                break
            }
            return nil
        }
        /// Reads a quoted or bare token; returns nil with an issue if malformed.
        func readToken() -> (String?, ValidationResult?) {
            guard i < units.count else { return (nil, nil) }
            if units[i] == 0x22 {
                let start = (line, column, i)
                advance()
                var value: [UInt16] = []
                while i < units.count {
                    let c = units[i]
                    if c == 0x5C { advance(); if i < units.count { value.append(units[i]); advance() }; continue }
                    if c == 0x22 { advance(); return (String(utf16CodeUnits: value, count: value.count), nil) }
                    value.append(c)
                    advance()
                }
                return (nil, .issue(SyntaxIssue(message: String(localized: "Unterminated string"), line: start.0, column: start.1, utf16Offset: start.2)))
            }
            var value: [UInt16] = []
            while i < units.count, isBare(units[i]) { value.append(units[i]); advance() }
            if value.isEmpty { return (nil, issue(String(localized: "Unexpected '\(String(utf16CodeUnits: [units[i]], count: 1))', a key was expected"))) }
            return (String(utf16CodeUnits: value, count: value.count), nil)
        }

        while true {
            if let problem = skipTrivia() { return problem }
            guard i < units.count else { break }
            let keyLine = line, keyColumn = column, keyOffset = i
            let (key, keyProblem) = readToken()
            if let keyProblem { return keyProblem }
            guard let key else { break }
            if let problem = skipTrivia() { return problem }
            guard i < units.count, units[i] == 0x3D else { return issue(String(localized: "'=' expected after the key \"\(key)\"")) }
            advance()
            if let problem = skipTrivia() { return problem }
            guard i < units.count, units[i] == 0x22 else { return issue(String(localized: "A quoted value was expected for \"\(key)\"")) }
            let (_, valueProblem) = readToken()
            if let valueProblem { return valueProblem }
            if let problem = skipTrivia() { return problem }
            guard i < units.count, units[i] == 0x3B else { return issue(String(localized: "';' expected after the value of \"\(key)\"")) }
            advance()
            if !keys.insert(key).inserted {
                return .issue(SyntaxIssue(message: String(localized: "Duplicate key \"\(key)\""), line: keyLine, column: keyColumn, utf16Offset: keyOffset))
            }
            count += 1
        }
        return .valid(String(localized: "Valid strings file, entries: \(count)"))
    }

    private static func isBare(_ c: UInt16) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x2E || c == 0x2D
    }
}

/// Xcode string catalogs: strict JSON, then every key must carry each language the catalog uses.
nonisolated enum XCStringsChecker {
    static func check(_ text: String, json: ValidationResult) -> ValidationResult {
        guard case .valid = json else { return json }
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else {
            return .issue(SyntaxIssue(message: String(localized: "Not a string catalog: no \"strings\" object"), line: 1, column: 1, utf16Offset: 0))
        }
        let source = root["sourceLanguage"] as? String ?? "en"
        var languages: Set<String> = []
        for case let entry as [String: Any] in strings.values {
            if let localizations = entry["localizations"] as? [String: Any] {
                languages.formUnion(localizations.keys)
            }
        }
        languages.remove(source)
        let ordered = languages.sorted()

        for key in strings.keys.sorted() {
            let entry = strings[key] as? [String: Any] ?? [:]
            if entry["shouldTranslate"] as? Bool == false { continue }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let missing = ordered.filter { language in
                guard let localization = localizations[language] as? [String: Any] else { return true }
                if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
                    return value.isEmpty
                }
                return localization["variations"] == nil && localization["substitutions"] == nil
            }
            if !missing.isEmpty {
                let (line, column, offset) = locate(key: key, in: text)
                let languages = missing.joined(separator: ", ")
                return .issue(SyntaxIssue(
                    message: String(localized: "\"\(key)\" has no \(languages) translation"),
                    line: line, column: column, utf16Offset: offset
                ))
            }
        }
        let summary = ordered.isEmpty ? String(localized: "source language only") : ordered.joined(separator: ", ")
        return .valid(String(localized: "String catalog, keys: \(strings.count), languages: \(summary)"))
    }

    private static func locate(key: String, in text: String) -> (Int, Int, Int) {
        let escaped = "\"" + key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        guard let range = text.range(of: escaped + " : {") ?? text.range(of: escaped + ": {") ?? text.range(of: escaped) else {
            return (1, 1, 0)
        }
        let offset = text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound.samePosition(in: text.utf16) ?? text.utf16.startIndex)
        let prefix = text[..<range.lowerBound]
        let line = prefix.filter { $0 == "\n" }.count + 1
        let column = prefix.split(separator: "\n", omittingEmptySubsequences: false).last?.utf16.count ?? 0
        return (line, column + 1, offset)
    }
}
