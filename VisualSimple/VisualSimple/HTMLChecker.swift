//
//  HTMLChecker.swift
//  VisualSimple
//

import Foundation

/// Tag pairing for HTML: void elements need no end tag, elements whose end tag is
/// optional are closed implicitly, everything else must be closed in order.
nonisolated enum HTMLChecker {
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr",
    ]
    private static let optionalEnd: Set<String> = [
        "html", "head", "body", "p", "li", "dt", "dd", "option", "optgroup",
        "thead", "tbody", "tfoot", "tr", "td", "th", "colgroup", "caption", "rp", "rt",
    ]
    private static let rawText: Set<String> = ["script", "style", "textarea", "title"]

    private struct OpenTag {
        let name: String
        let line: Int
        let column: Int
        let offset: Int
    }

    static func check(_ text: String) -> ValidationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notApplicable }
        let units = Array(text.utf16)
        var i = 0
        var line = 1
        var column = 1
        var stack: [OpenTag] = []

        func advance(_ count: Int = 1) {
            for _ in 0..<count where i < units.count {
                if units[i] == 0x0A { line += 1; column = 1 } else { column += 1 }
                i += 1
            }
        }
        func matches(_ s: String) -> Bool {
            let m = Array(s.lowercased().utf16)
            guard i + m.count <= units.count else { return false }
            for (k, unit) in m.enumerated() where lower(units[i + k]) != unit { return false }
            return true
        }
        func skipUntil(_ s: String) -> Bool {
            while i < units.count {
                if matches(s) { advance(s.utf16.count); return true }
                advance()
            }
            return false
        }

        while i < units.count {
            guard units[i] == 0x3C else { advance(); continue } // '<'
            let tagLine = line, tagColumn = column, tagOffset = i

            if matches("<!--") {
                if !skipUntil("-->") {
                    return .issue(SyntaxIssue(message: String(localized: "Unterminated comment"), line: tagLine, column: tagColumn, utf16Offset: tagOffset))
                }
                continue
            }
            if matches("<![cdata[") {
                if !skipUntil("]]>") {
                    return .issue(SyntaxIssue(message: String(localized: "Unterminated CDATA section"), line: tagLine, column: tagColumn, utf16Offset: tagOffset))
                }
                continue
            }
            if matches("<!") || matches("<?") {
                _ = skipUntil(">")
                continue
            }

            advance()
            let closing = i < units.count && units[i] == 0x2F // '/'
            if closing { advance() }
            var nameUnits: [UInt16] = []
            while i < units.count, isNameUnit(units[i]) {
                nameUnits.append(lower(units[i]))
                advance()
            }
            guard !nameUnits.isEmpty else { continue } // a bare '<' in text
            let name = String(utf16CodeUnits: nameUnits, count: nameUnits.count)

            // Attributes until '>' (quotes may contain '>').
            var selfClosing = false
            var quoteUnit: UInt16?
            var quoteLine = line, quoteColumn = column, quoteOffset = i
            var closed = false
            while i < units.count {
                let unit = units[i]
                if let q = quoteUnit {
                    if unit == q { quoteUnit = nil }
                } else if unit == 0x22 || unit == 0x27 {
                    quoteUnit = unit
                    quoteLine = line; quoteColumn = column; quoteOffset = i
                } else if unit == 0x3E {
                    closed = true
                    advance()
                    break
                } else if unit == 0x2F, i + 1 < units.count, units[i + 1] == 0x3E {
                    selfClosing = true
                }
                advance()
            }
            if quoteUnit != nil {
                return .issue(SyntaxIssue(message: String(localized: "Unterminated attribute value in <\(name)>"), line: quoteLine, column: quoteColumn, utf16Offset: quoteOffset))
            }
            if !closed {
                return .issue(SyntaxIssue(message: String(localized: "Tag <\(name)> is never closed with '>'"), line: tagLine, column: tagColumn, utf16Offset: tagOffset))
            }

            if closing {
                if let index = stack.lastIndex(where: { $0.name == name }) {
                    // Everything above must have an optional end tag, otherwise it was left open.
                    if let stray = stack[(index + 1)...].last(where: { !optionalEnd.contains($0.name) }) {
                        return .issue(SyntaxIssue(message: String(localized: "Expected </\(stray.name)> (opened line \(stray.line)) before </\(name)>"), line: tagLine, column: tagColumn, utf16Offset: tagOffset))
                    }
                    stack.removeSubrange(index...)
                } else if !optionalEnd.contains(name) && !voidElements.contains(name) {
                    return .issue(SyntaxIssue(message: String(localized: "Closing tag </\(name)> has no opening tag"), line: tagLine, column: tagColumn, utf16Offset: tagOffset))
                }
                continue
            }

            if voidElements.contains(name) || selfClosing { continue }
            if rawText.contains(name) {
                if !skipUntil("</\(name)") {
                    return .issue(SyntaxIssue(message: String(localized: "Unclosed <\(name)>"), line: tagLine, column: tagColumn, utf16Offset: tagOffset))
                }
                _ = skipUntil(">")
                continue
            }
            // A new <li>, <p>, <td>... closes the previous one at the same level.
            if optionalEnd.contains(name), let last = stack.last, last.name == name {
                stack.removeLast()
            }
            stack.append(OpenTag(name: name, line: tagLine, column: tagColumn, offset: tagOffset))
        }

        if let open = stack.last(where: { !optionalEnd.contains($0.name) }) {
            return .issue(SyntaxIssue(message: String(localized: "Unclosed <\(open.name)>"), line: open.line, column: open.column, utf16Offset: open.offset))
        }
        return .valid(String(localized: "HTML: tags balanced"))
    }

    private static func lower(_ unit: UInt16) -> UInt16 {
        (unit >= 0x41 && unit <= 0x5A) ? unit + 0x20 : unit
    }

    private static func isNameUnit(_ unit: UInt16) -> Bool {
        (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x2D || unit == 0x5F || unit == 0x3A
    }
}
