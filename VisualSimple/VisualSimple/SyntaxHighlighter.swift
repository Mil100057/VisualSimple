//
//  SyntaxHighlighter.swift
//  VisualSimple
//

import AppKit

enum SyntaxLanguage {
    case plain
    case json
    case yaml
    case html
    case xml
    case markdown
    case swift
    case css
    case javascript
    case ini
    case dockerfile
    case makefile
    case shell
    case python
    case ruby
    case perl
    case php
    case powershell
    case sql
    case rust
    case go
    case c
    case java
    case kotlin
    case typescript
    case strings
    case toml

    static func from(format: SaveFormat) -> SyntaxLanguage {
        switch format {
        case .none: .plain
        case .json: .json
        case .yaml: .yaml
        case .html: .html
        case .xml: .xml
        case .md: .markdown
        case .swift: .swift
        case .css: .css
        case .js: .javascript
        case .sh: .shell
        case .ini, .env: .ini
        case .toml: .toml
        case .txt, .csv, .tsv, .log: .plain
        case .sql: .sql
        case .rs: .rust
        case .go: .go
        case .c, .cpp, .m: .c
        case .java: .java
        case .kt: .kotlin
        case .ts: .typescript
        case .plist: .xml
        case .strings: .strings
        }
    }

    private static let extensionMap: [String: SyntaxLanguage] = [
        "sh": .shell, "bash": .shell, "zsh": .shell, "fish": .shell,
        "command": .shell, "awk": .shell, "sed": .shell,
        "py": .python, "pyw": .python,
        "rb": .ruby,
        "pl": .perl, "pm": .perl,
        "php": .php,
        "ps1": .powershell, "psm1": .powershell,
        "js": .javascript, "jsx": .javascript, "mjs": .javascript, "cjs": .javascript,
        "ts": .typescript, "tsx": .typescript,
        "lua": .shell,
        "sql": .sql,
        "gradle": .kotlin,
        "rs": .rust,
        "go": .go,
        "c": .c, "h": .c, "cpp": .c, "cc": .c, "cxx": .c, "hpp": .c, "hh": .c, "m": .c, "mm": .c,
        "java": .java,
        "kt": .kotlin, "kts": .kotlin,
        "toml": .toml,
        "plist": .xml, "entitlements": .xml, "gpx": .xml,
        "canvas": .json, "excalidraw": .json, "xcstrings": .json,
        "strings": .strings,
    ]

    static func resolve(url: URL?, format: SaveFormat) -> SyntaxLanguage {
        if let url {
            if url.lastPathComponent.lowercased().hasPrefix(".env") { return .ini }
            if url.pathExtension.isEmpty {
                switch url.lastPathComponent.lowercased() {
                case "dockerfile", "containerfile": return .dockerfile
                case "makefile": return .makefile
                default: break
                }
            } else {
                let ext = url.pathExtension.lowercased()
                if let lang = extensionMap[ext] { return lang }
            }
        }
        return from(format: format)
    }
}

struct SyntaxHighlighter {
    static func highlight(
        _ text: String,
        language: SyntaxLanguage,
        theme: SyntaxTheme,
        font: NSFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: theme.plain]
        )
        guard !text.isEmpty else { return result }

        switch language {
        case .plain: break
        case .json: highlightJSON(in: result, theme: theme)
        case .yaml: highlightYAML(in: result, theme: theme)
        case .html: highlightHTML(in: result, theme: theme)
        case .xml: highlightXML(in: result, theme: theme)
        case .markdown: highlightMarkdown(in: result, theme: theme)
        case .swift: highlightSwift(in: result, theme: theme)
        case .css: highlightCSS(in: result, theme: theme)
        case .javascript: highlightJavaScript(in: result, theme: theme)
        case .ini: highlightINI(in: result, theme: theme)
        case .dockerfile: highlightDockerfile(in: result, theme: theme)
        case .makefile: highlightMakefile(in: result, theme: theme)
        case .shell: highlightShell(in: result, theme: theme)
        case .python: highlightPython(in: result, theme: theme)
        case .ruby: highlightRuby(in: result, theme: theme)
        case .perl: highlightPerl(in: result, theme: theme)
        case .php: highlightPHP(in: result, theme: theme)
        case .powershell: highlightPowerShell(in: result, theme: theme)
        case .sql: highlightSQL(in: result, theme: theme)
        case .rust: highlightRust(in: result, theme: theme)
        case .go: highlightGo(in: result, theme: theme)
        case .c: highlightC(in: result, theme: theme)
        case .java: highlightJava(in: result, theme: theme)
        case .kotlin: highlightKotlin(in: result, theme: theme)
        case .typescript: highlightTypeScript(in: result, theme: theme)
        case .strings: highlightStrings(in: result, theme: theme)
        case .toml: highlightINI(in: result, theme: theme)
        }

        return result
    }

    static func apply(_ kind: SyntaxTokenKind, theme: SyntaxTheme, to range: NSRange, in text: NSMutableAttributedString) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        text.addAttribute(.foregroundColor, value: theme.color(for: kind), range: range)
    }

    static func highlightPattern(
        _ pattern: String,
        in text: NSMutableAttributedString,
        kind: SyntaxTokenKind,
        theme: SyntaxTheme,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            apply(kind, theme: theme, to: match.range, in: text)
        }
    }

    // MARK: - JSON

    private static func highlightJSON(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#""(?:\\.|[^"\\])*""#, in: text, kind: .string, theme: theme)
        highlightPattern(#"\b(true|false|null)\b"#, in: text, kind: .boolean, theme: theme)
        highlightPattern(#"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#, in: text, kind: .number, theme: theme)
        highlightPattern(#""(?:\\.|[^"\\])*"(?=\s*:)"#, in: text, kind: .key, theme: theme)
        highlightPattern(#"[{}\[\],:]"#, in: text, kind: .punctuation, theme: theme)
    }

    // MARK: - YAML

    private static func highlightYAML(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"#[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"(?m)^---|^\.\.\."#, in: text, kind: .punctuation, theme: theme)
        highlightPattern(#"(?m)^[\t ]*[\w.-]+(?=\s*:)"#, in: text, kind: .key, theme: theme)
        highlightPattern(#"(?<=[:\s])[\-+]?\d+(?:\.\d+)?"#, in: text, kind: .number, theme: theme)
        highlightPattern(#"(?i)\b(true|false|null|yes|no|on|off)\b"#, in: text, kind: .boolean, theme: theme)
        highlightPattern(#"'(?:\\.|[^'\\])*'|"[^"\n]*""#, in: text, kind: .string, theme: theme)
    }

    // MARK: - HTML

    private static func highlightHTML(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"<!--[\s\S]*?-->"#, in: text, kind: .comment, theme: theme, options: [.dotMatchesLineSeparators])
        highlightPattern(#"(?i)<!DOCTYPE[^>]*>"#, in: text, kind: .keyword, theme: theme)
        highlightPattern(#"(?<=<)\/?[\w:-]+"#, in: text, kind: .tag, theme: theme)
        highlightPattern(#"\b[\w:-]+(?==)"#, in: text, kind: .attribute, theme: theme)
        highlightPattern(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, in: text, kind: .string, theme: theme)
    }

    // MARK: - XML

    private static func highlightXML(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightHTML(in: text, theme: theme)
    }

    // MARK: - Markdown

    private static func highlightMarkdown(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"(?m)^#{1,6}\s.+$"#, in: text, kind: .heading, theme: theme)
        highlightPattern(#"`[^`\n]+`"#, in: text, kind: .code, theme: theme)
        highlightPattern(#"\*\*[^*\n]+\*\*|__[^_\n]+__"#, in: text, kind: .keyword, theme: theme)
        highlightPattern(#"(?<!\*)\*(?!\*)[^*\n]+\*(?!\*)|(?<!_)_(?!_)[^_\n]+_(?!_)"#, in: text, kind: .attribute, theme: theme)
        highlightPattern(#"\[[^\]]+\]\([^\)]+\)"#, in: text, kind: .link, theme: theme)
        highlightPattern(#"(?m)^>\s.+$"#, in: text, kind: .comment, theme: theme)
    }

    // MARK: - Swift

    private static func highlightSwift(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        let keywords = [
            "import", "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
            "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat", "break",
            "continue", "return", "throw", "try", "catch", "async", "await", "actor", "private",
            "public", "internal", "fileprivate", "open", "static", "final", "override", "mutating",
            "nonmutating", "init", "deinit", "self", "Self", "super", "nil", "true", "false",
            "in", "where", "as", "is", "some", "any", "typealias", "associatedtype", "get", "set",
            "willSet", "didSet", "subscript", "operator", "precedencegroup", "inout", "lazy",
            "weak", "unowned", "defer", "do", "throws", "rethrows", "convenience", "required",
            "optional", "dynamic", "indirect", "lazy", "nonisolated", "isolated", "distributed",
            "macro", "package"
        ]
        let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        highlightPattern(#"//[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"/\*[\s\S]*?\*/"#, in: text, kind: .comment, theme: theme, options: [.dotMatchesLineSeparators])
        highlightPattern(#""(?:\\.|[^"\\])*""#, in: text, kind: .string, theme: theme)
        highlightPattern(keywordPattern, in: text, kind: .keyword, theme: theme)
        highlightPattern(#"\b\d+(?:\.\d+)?\b"#, in: text, kind: .number, theme: theme)
    }

    // MARK: - CSS

    private static func highlightCSS(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"/\*[\s\S]*?\*/"#, in: text, kind: .comment, theme: theme, options: [.dotMatchesLineSeparators])
        highlightPattern(#"(?i)@[\w-]+"#, in: text, kind: .keyword, theme: theme)
        highlightPattern(#"(?<=[{;,\s])[\w-]+(?=\s*:)"#, in: text, kind: .key, theme: theme)
        highlightPattern(#"(?i)\b(?:rgb|rgba|hsl|hsla|url|calc|var|important)\b"#, in: text, kind: .keyword, theme: theme)
        highlightPattern(#"(?<=\.)[\w-]+"#, in: text, kind: .attribute, theme: theme)
        highlightPattern(#"(?<=[\s{])[.#]?[\w-]+(?=\s*[{,])"#, in: text, kind: .tag, theme: theme)
        highlightPattern(#"#(?:[0-9a-fA-F]{3,8})\b"#, in: text, kind: .number, theme: theme)
        highlightPattern(#"(?<![\w-])\d+(?:\.\d+)?(?:px|em|rem|vh|vw|%|s|ms|deg|fr)?"#, in: text, kind: .number, theme: theme)
        highlightPattern(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, in: text, kind: .string, theme: theme)
    }

    // MARK: - JavaScript

    private static func highlightJavaScript(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        let keywords = [
            "import", "export", "from", "default", "const", "let", "var", "function", "class",
            "extends", "new", "return", "if", "else", "for", "while", "do", "switch", "case",
            "break", "continue", "try", "catch", "finally", "throw", "async", "await", "typeof",
            "instanceof", "in", "of", "null", "undefined", "true", "false", "this", "super",
            "yield", "delete", "void", "with", "debugger", "static", "get", "set"
        ]
        let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        highlightPattern(#"//[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"/\*[\s\S]*?\*/"#, in: text, kind: .comment, theme: theme, options: [.dotMatchesLineSeparators])
        highlightPattern(#"(?<![\\])"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#, in: text, kind: .string, theme: theme)
        highlightPattern(keywordPattern, in: text, kind: .keyword, theme: theme)
        highlightPattern(#"\b\d+(?:\.\d+)?\b"#, in: text, kind: .number, theme: theme)
    }

    // MARK: - INI / TOML / ENV

    private static func highlightINI(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"#[^\n]*|//[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"(?m)^\[[^\]]+\]"#, in: text, kind: .tag, theme: theme)
        highlightPattern(#"(?m)^[\w.-]+(?=\s*=)"#, in: text, kind: .key, theme: theme)
        highlightPattern(#"(?<==\s*)[^\n#]+"#, in: text, kind: .string, theme: theme)
    }

    // MARK: - Dockerfile

    private static func highlightDockerfile(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"(?m)^#[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"(?i)^(?:FROM|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\b"#, in: text, kind: .keyword, theme: theme)
        highlightPattern(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, in: text, kind: .string, theme: theme)
        highlightPattern(#"(?<=\s)--[\w-]+"#, in: text, kind: .attribute, theme: theme)
    }

    // MARK: - Makefile

    private static func highlightMakefile(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"(?m)^[^\n#:]+(?=:)"#, in: text, kind: .key, theme: theme)
        highlightPattern(#"(?m)^\t[^\n]+"#, in: text, kind: .string, theme: theme)
        highlightPattern(#"#[^\n]*"#, in: text, kind: .comment, theme: theme)
    }

    // MARK: - Shell (sh, bash, zsh, fish, awk…)

    private static func highlightShell(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"(?m)^#![^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"(?<![\\])"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\$'(?:\\.|[^'\\])*'"#, in: text, kind: .string, theme: theme)
        highlightPattern(#"(?<![\\])#(?:\\.|[^\\"\n])*(?="|$)|(?<!['"])\s#[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"\$\{[^}]+\}|\$[\w@*#?$!-]+"#, in: text, kind: .attribute, theme: theme)
        let keywords = [
            "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac",
            "in", "function", "select", "until", "return", "exit", "break", "continue", "local",
            "export", "readonly", "declare", "unset", "set", "shift", "source", "trap", "eval",
            "exec", "wait", "true", "false", "alias", "unalias", "cd", "echo", "printf", "read"
        ]
        highlightPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", in: text, kind: .keyword, theme: theme)
        highlightPattern(#"\b\d+\b"#, in: text, kind: .number, theme: theme)
        highlightPattern(#"(?i)\b(?:sudo|chmod|chown|grep|sed|awk|curl|wget|docker|git|npm|yarn|pip|brew)\b"#, in: text, kind: .tag, theme: theme)
    }

    // MARK: - Python

    private static func highlightPython(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"#[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"(?m)^\s*"""[\s\S]*?"""|^\s*'''[\s\S]*?'''"#, in: text, kind: .comment, theme: theme, options: [.dotMatchesLineSeparators])
        highlightPattern(#"(?<![\\])"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|"""(?:\\.|[^"\\])*"""|'''(?:\\.|[^'\\])*'''"#, in: text, kind: .string, theme: theme)
        let keywords = [
            "def", "class", "import", "from", "as", "if", "elif", "else", "for", "while", "try",
            "except", "finally", "with", "return", "yield", "raise", "pass", "break", "continue",
            "lambda", "global", "nonlocal", "assert", "del", "in", "is", "not", "and", "or",
            "True", "False", "None", "async", "await", "self"
        ]
        highlightPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", in: text, kind: .keyword, theme: theme)
        highlightPattern(#"\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, in: text, kind: .number, theme: theme)
        highlightPattern(#"@\w+"#, in: text, kind: .attribute, theme: theme)
    }

    // MARK: - Ruby

    private static func highlightRuby(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"#[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"(?<![\\])"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, in: text, kind: .string, theme: theme)
        let keywords = [
            "def", "class", "module", "end", "if", "elsif", "else", "unless", "case", "when",
            "while", "until", "for", "do", "begin", "rescue", "ensure", "return", "yield",
            "break", "next", "redo", "retry", "raise", "require", "include", "extend", "attr",
            "true", "false", "nil", "self", "super", "defined?", "alias", "undef", "lambda"
        ]
        highlightPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", in: text, kind: .keyword, theme: theme)
        highlightPattern(#":\w+"#, in: text, kind: .attribute, theme: theme)
        highlightPattern(#"\b\d+(?:\.\d+)?\b"#, in: text, kind: .number, theme: theme)
    }

    // MARK: - Perl

    private static func highlightPerl(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"#[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"(?<![\\])"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, in: text, kind: .string, theme: theme)
        let keywords = [
            "my", "our", "local", "sub", "package", "use", "require", "if", "elsif", "else",
            "unless", "while", "until", "for", "foreach", "do", "return", "last", "next", "redo",
            "given", "when", "default", "print", "say", "die", "warn", "true", "false", "undef"
        ]
        highlightPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", in: text, kind: .keyword, theme: theme)
        highlightPattern(#"\$\w+"#, in: text, kind: .attribute, theme: theme)
        highlightPattern(#"\b\d+(?:\.\d+)?\b"#, in: text, kind: .number, theme: theme)
    }

    // MARK: - PHP

    private static func highlightPHP(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/"#, in: text, kind: .comment, theme: theme, options: [.dotMatchesLineSeparators])
        highlightPattern(#"(?<![\\])"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, in: text, kind: .string, theme: theme)
        let keywords = [
            "function", "class", "interface", "trait", "namespace", "use", "extends", "implements",
            "public", "private", "protected", "static", "final", "abstract", "if", "else", "elseif",
            "switch", "case", "default", "for", "foreach", "while", "do", "return", "new", "echo",
            "true", "false", "null", "array", "as", "try", "catch", "finally", "throw", "global"
        ]
        highlightPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", in: text, kind: .keyword, theme: theme)
        highlightPattern(#"\$\w+"#, in: text, kind: .attribute, theme: theme)
        highlightPattern(#"\b\d+(?:\.\d+)?\b"#, in: text, kind: .number, theme: theme)
    }

    // MARK: - PowerShell

    private static func highlightPowerShell(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"#[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"(?<![\\])"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, in: text, kind: .string, theme: theme)
        let keywords = [
            "function", "param", "if", "else", "elseif", "switch", "foreach", "for", "while", "do",
            "until", "return", "break", "continue", "try", "catch", "finally", "throw", "class",
            "enum", "true", "false", "null", "in", "not", "and", "or", "begin", "process", "end"
        ]
        highlightPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", in: text, kind: .keyword, theme: theme)
        highlightPattern(#"-\w+\b|\$\w+"#, in: text, kind: .attribute, theme: theme)
        highlightPattern(#"\b\d+(?:\.\d+)?\b"#, in: text, kind: .number, theme: theme)
        highlightPattern(#"(?i)\b(?:Write-Host|Write-Output|Get-|Set-|New-|Remove-|Import-|Export-)\S*"#, in: text, kind: .tag, theme: theme)
    }
}
