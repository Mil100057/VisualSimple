//
//  SyntaxTheme.swift
//  VisualSimple
//

import AppKit

enum SyntaxTokenKind {
    case plain
    case keyword
    case string
    case number
    case comment
    case tag
    case attribute
    case key
    case boolean
    case heading
    case code
    case link
    case punctuation
}

struct SyntaxTheme {
    let plain: NSColor
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let tag: NSColor
    let attribute: NSColor
    let key: NSColor
    let boolean: NSColor
    let heading: NSColor
    let code: NSColor
    let link: NSColor
    let punctuation: NSColor

    func color(for kind: SyntaxTokenKind) -> NSColor {
        switch kind {
        case .plain: plain
        case .keyword: keyword
        case .string: string
        case .number: number
        case .comment: comment
        case .tag: tag
        case .attribute: attribute
        case .key: key
        case .boolean: boolean
        case .heading: heading
        case .code: code
        case .link: link
        case .punctuation: punctuation
        }
    }

    static func obsidian(isDark: Bool) -> SyntaxTheme {
        if isDark {
            return SyntaxTheme(
                plain: NSColor(hex: "dadada"),
                keyword: NSColor(hex: "569cd6"),
                string: NSColor(hex: "ce9178"),
                number: NSColor(hex: "b5cea8"),
                comment: NSColor(hex: "6a9955"),
                tag: NSColor(hex: "569cd6"),
                attribute: NSColor(hex: "9cdcfe"),
                key: NSColor(hex: "9cdcfe"),
                boolean: NSColor(hex: "569cd6"),
                heading: NSColor(hex: "a882ff"),
                code: NSColor(hex: "ce9178"),
                link: NSColor(hex: "a882ff"),
                punctuation: NSColor(hex: "808080")
            )
        }
        return SyntaxTheme(
            plain: NSColor(hex: "222222"),
            keyword: NSColor(hex: "0000ff"),
            string: NSColor(hex: "a31515"),
            number: NSColor(hex: "098658"),
            comment: NSColor(hex: "008000"),
            tag: NSColor(hex: "800000"),
            attribute: NSColor(hex: "ff0000"),
            key: NSColor(hex: "001080"),
            boolean: NSColor(hex: "0000ff"),
            heading: NSColor(hex: "7852ee"),
            code: NSColor(hex: "a31515"),
            link: NSColor(hex: "7852ee"),
            punctuation: NSColor(hex: "666666")
        )
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
