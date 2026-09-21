//
//  MarkdownRenderer.swift
//  VisualSimple
//

import AppKit
import SwiftUI

/// Block structure is split by hand (headings, lists, fences, quotes, rules, tables);
/// inline emphasis, code and links come from Foundation's Markdown parser.
enum MarkdownRenderer {
    struct Palette {
        let text: NSColor
        let secondary: NSColor
        let accent: NSColor
        let codeBackground: NSColor
        let rule: NSColor
    }

    static func render(_ markdown: String, palette: Palette) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: " ")
            result.append(inline(text, font: bodyFont, palette: palette, spacingAfter: 10))
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let marker = String(trimmed.prefix { $0 == trimmed.first! })
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                    code.append(lines[i])
                    i += 1
                }
                i += 1
                result.append(codeBlock(code.joined(separator: "\n"), palette: palette))
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }
            if let level = headingLevel(trimmed) {
                flushParagraph()
                let title = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                let size: CGFloat = [26, 22, 18, 16, 14, 13][level - 1]
                let font = NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
                result.append(inline(title, font: font, palette: palette, spacingBefore: level == 1 ? 6 : 12, spacingAfter: 8))
                i += 1
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                result.append(rule(palette: palette))
                i += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                let font = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
                result.append(inline(quote.joined(separator: " "), font: font, palette: palette, color: palette.secondary, indent: 20, spacingAfter: 10))
                continue
            }
            if let item = listItem(line) {
                flushParagraph()
                while i < lines.count, let item = listItem(lines[i]) {
                    let indent = CGFloat(20 + item.depth * 20)
                    let bullet = item.ordinal.map { "\($0)." } ?? "•"
                    result.append(inline(bullet + "\u{2003}" + item.text, font: bodyFont, palette: palette, indent: indent, headIndent: indent + 18, spacingAfter: 3))
                    i += 1
                }
                _ = item
                continue
            }
            if trimmed.hasPrefix("|"), i + 1 < lines.count, lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                flushParagraph()
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let cells = lines[i].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if !cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } && !$0.isEmpty }) {
                        rows.append(cells)
                    }
                    i += 1
                }
                result.append(table(rows, palette: palette))
                continue
            }
            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        return result
    }

    private static let bodyFont = NSFont.systemFont(ofSize: 14)
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    private static func headingLevel(_ trimmed: String) -> Int? {
        let level = trimmed.prefix { $0 == "#" }.count
        guard level >= 1, level <= 6, trimmed.count > level, trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)] == " " else { return nil }
        return level
    }

    private static func listItem(_ line: String) -> (depth: Int, ordinal: Int?, text: String)? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(leading.count)
        let depth = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            var text = String(rest.dropFirst(2))
            if text.hasPrefix("[ ] ") { text = "☐ " + text.dropFirst(4) }
            if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { text = "☑ " + text.dropFirst(4) }
            return (depth, nil, text)
        }
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, rest.dropFirst(digits.count).hasPrefix(". ") {
            return (depth, Int(digits), String(rest.dropFirst(digits.count + 2)))
        }
        return nil
    }

    /// Inline Markdown through Foundation, then fonts and colors for its intents.
    private static func inline(
        _ text: String, font: NSFont, palette: Palette, color: NSColor? = nil,
        indent: CGFloat = 0, headIndent: CGFloat? = nil, spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 6
    ) -> NSAttributedString {
        let cleaned = text.replacingOccurrences(of: #"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"#, with: "[$1]($1)", options: .regularExpression)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        let parsed = (try? AttributedString(markdown: cleaned, options: options)) ?? AttributedString(text)

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = headIndent ?? indent
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.lineSpacing = 2

        let output = NSMutableAttributedString()
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            var runFont = font
            var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: style, .foregroundColor: color ?? palette.text]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask) }
                if intent.contains(.code) {
                    runFont = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1.5, weight: .regular)
                    attributes[.backgroundColor] = palette.codeBackground
                }
                if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = palette.accent
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            attributes[.font] = runFont
            output.append(NSAttributedString(string: piece, attributes: attributes))
        }
        output.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: style]))
        return output
    }

    private static func codeBlock(_ code: String, palette: Palette) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.paragraphSpacing = 10
        return NSAttributedString(string: code + "\n", attributes: [
            .font: codeFont, .foregroundColor: palette.text, .backgroundColor: palette.codeBackground, .paragraphStyle: style,
        ])
    }

    private static func rule(palette: Palette) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 10
        style.alignment = .center
        return NSAttributedString(string: "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n", attributes: [
            .font: bodyFont, .foregroundColor: palette.rule, .paragraphStyle: style,
        ])
    }

    private static func table(_ rows: [[String]], palette: Palette) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let columns = rows.map(\.count).max() ?? 0
        let style = NSMutableParagraphStyle()
        style.tabStops = (1...max(1, columns)).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * 140) }
        style.paragraphSpacing = 2
        for (index, row) in rows.enumerated() {
            let font = index == 0 ? NSFont.boldSystemFont(ofSize: 13) : NSFont.systemFont(ofSize: 13)
            let line = row.joined(separator: "\t")
            output.append(inline(line, font: font, palette: palette, spacingAfter: 2).withParagraphStyle(style))
        }
        output.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
        return output
    }
}

private extension NSAttributedString {
    func withParagraphStyle(_ style: NSParagraphStyle) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: self)
        copy.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: copy.length))
        return copy
    }
}

/// Read-only rendered view of a Markdown document, refreshed when the text changes.
struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let theme: EditorTheme
    let isDark: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        apply(to: textView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if context.coordinator.lastMarkdown != markdown || context.coordinator.lastDark != isDark {
            apply(to: textView, context: context)
        }
    }

    private func apply(to textView: NSTextView, context: Context) {
        context.coordinator.lastMarkdown = markdown
        context.coordinator.lastDark = isDark
        let palette = MarkdownRenderer.Palette(
            text: NSColor(theme.textPrimary),
            secondary: NSColor(theme.textSecondary),
            accent: NSColor(theme.accent),
            codeBackground: NSColor(theme.backgroundSecondary),
            rule: NSColor(theme.divider)
        )
        textView.backgroundColor = NSColor(theme.backgroundPrimary)
        let visible = textView.enclosingScrollView?.contentView.bounds.origin
        textView.textStorage?.setAttributedString(MarkdownRenderer.render(markdown, palette: palette))
        if let visible {
            textView.enclosingScrollView?.contentView.scroll(to: visible)
            textView.enclosingScrollView?.reflectScrolledClipView(textView.enclosingScrollView!.contentView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastMarkdown: String?
        var lastDark = false
    }
}
