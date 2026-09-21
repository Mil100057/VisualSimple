//
//  SyntaxHighlighter+Languages.swift
//  VisualSimple
//

import AppKit

/// Languages added on 09/09/2026. Same regex approach as the original set.
extension SyntaxHighlighter {
    private static func highlightCFamily(
        keywords: [String],
        in text: NSMutableAttributedString,
        theme: SyntaxTheme,
        extraStrings: String? = nil,
        caseInsensitive: Bool = false
    ) {
        let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        highlightPattern(#"//[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"/\*[\s\S]*?\*/"#, in: text, kind: .comment, theme: theme, options: [.dotMatchesLineSeparators])
        highlightPattern(#""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#, in: text, kind: .string, theme: theme)
        if let extraStrings {
            highlightPattern(extraStrings, in: text, kind: .string, theme: theme, options: [.dotMatchesLineSeparators])
        }
        highlightPattern(keywordPattern, in: text, kind: .keyword, theme: theme, options: caseInsensitive ? [.caseInsensitive] : [])
        highlightPattern(#"\b0[xX][0-9a-fA-F_]+\b|\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, in: text, kind: .number, theme: theme)
    }

    static func highlightSQL(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        let keywords = [
            "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create",
            "table", "view", "index", "drop", "alter", "add", "column", "primary", "key", "foreign",
            "references", "not", "null", "default", "unique", "check", "constraint", "join", "inner",
            "left", "right", "full", "outer", "cross", "on", "using", "group", "by", "order", "asc",
            "desc", "having", "limit", "offset", "union", "all", "distinct", "as", "and", "or", "in",
            "exists", "between", "like", "is", "case", "when", "then", "else", "end", "begin", "commit",
            "rollback", "transaction", "with", "recursive", "returning", "if", "replace", "temporary",
            "integer", "int", "text", "varchar", "char", "boolean", "real", "float", "double", "numeric",
            "decimal", "date", "datetime", "timestamp", "blob", "true", "false", "count", "sum", "avg",
            "min", "max", "coalesce", "cast", "pragma", "explain", "vacuum", "trigger", "procedure", "function",
        ]
        highlightPattern(#"--[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"/\*[\s\S]*?\*/"#, in: text, kind: .comment, theme: theme, options: [.dotMatchesLineSeparators])
        highlightPattern(#"'(?:''|[^'])*'"#, in: text, kind: .string, theme: theme)
        highlightPattern("\\b(" + keywords.joined(separator: "|") + ")\\b", in: text, kind: .keyword, theme: theme, options: [.caseInsensitive])
        highlightPattern(#"\b\d+(?:\.\d+)?\b"#, in: text, kind: .number, theme: theme)
    }

    static func highlightRust(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightCFamily(keywords: [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
            "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub",
            "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe",
            "use", "where", "while", "macro_rules", "u8", "u16", "u32", "u64", "u128", "usize", "i8", "i16",
            "i32", "i64", "i128", "isize", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option",
            "Result", "Some", "None", "Ok", "Err", "Box", "Rc", "Arc",
        ], in: text, theme: theme, extraStrings: "r#*\"[\\s\\S]*?\"#*")
    }

    static func highlightGo(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightCFamily(keywords: [
            "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for",
            "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select",
            "struct", "switch", "type", "var", "nil", "true", "false", "iota", "int", "int8", "int16", "int32",
            "int64", "uint", "uint8", "uint16", "uint32", "uint64", "float32", "float64", "string", "bool",
            "byte", "rune", "error", "any", "make", "new", "len", "cap", "append", "panic", "recover",
        ], in: text, theme: theme, extraStrings: "`[^`]*`")
    }

    static func highlightC(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightCFamily(keywords: [
            "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum",
            "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return",
            "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void",
            "volatile", "while", "bool", "true", "false", "NULL", "nullptr", "class", "namespace", "template",
            "typename", "public", "private", "protected", "virtual", "override", "new", "delete", "this",
            "try", "catch", "throw", "using", "constexpr", "auto", "std", "interface", "implementation",
            "property", "synthesize", "selector", "import", "include", "define", "ifdef", "ifndef", "endif",
            "pragma", "id", "self", "super", "nil", "YES", "NO", "BOOL", "NSString", "NSInteger",
        ], in: text, theme: theme)
        highlightPattern(#"(?m)^\s*#\s*\w+"#, in: text, kind: .tag, theme: theme)
        highlightPattern(#"@\w+"#, in: text, kind: .keyword, theme: theme)
    }

    static func highlightJava(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightCFamily(keywords: [
            "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const",
            "continue", "default", "do", "double", "else", "enum", "extends", "final", "finally", "float",
            "for", "goto", "if", "implements", "import", "instanceof", "int", "interface", "long", "native",
            "new", "package", "private", "protected", "public", "return", "short", "static", "strictfp",
            "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "void",
            "volatile", "while", "true", "false", "null", "var", "record", "sealed", "permits", "yield",
            "String", "Integer", "List", "Map", "Set", "Optional",
        ], in: text, theme: theme, extraStrings: "\"\"\"[\\s\\S]*?\"\"\"")
        highlightPattern(#"@\w+"#, in: text, kind: .attribute, theme: theme)
    }

    static func highlightKotlin(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightCFamily(keywords: [
            "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface",
            "is", "null", "object", "package", "return", "super", "this", "throw", "true", "try", "typealias",
            "val", "var", "when", "while", "by", "catch", "constructor", "delegate", "dynamic", "field",
            "file", "finally", "get", "import", "init", "param", "property", "receiver", "set", "setparam",
            "value", "where", "abstract", "actual", "annotation", "companion", "const", "crossinline", "data",
            "enum", "expect", "external", "final", "infix", "inline", "inner", "internal", "lateinit",
            "noinline", "open", "operator", "out", "override", "private", "protected", "public", "reified",
            "sealed", "suspend", "tailrec", "vararg", "Int", "Long", "String", "Boolean", "Double", "Float",
            "List", "Map", "Set", "Unit", "Any", "Nothing",
        ], in: text, theme: theme, extraStrings: "\"\"\"[\\s\\S]*?\"\"\"")
        highlightPattern(#"@\w+"#, in: text, kind: .attribute, theme: theme)
    }

    static func highlightTypeScript(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightCFamily(keywords: [
            "import", "export", "from", "default", "const", "let", "var", "function", "class", "extends",
            "new", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "try",
            "catch", "finally", "throw", "async", "await", "typeof", "instanceof", "in", "of", "null",
            "undefined", "true", "false", "this", "super", "yield", "delete", "void", "with", "debugger",
            "static", "get", "set", "type", "interface", "enum", "implements", "declare", "readonly",
            "namespace", "module", "abstract", "private", "public", "protected", "keyof", "unknown", "never",
            "any", "string", "number", "boolean", "object", "symbol", "bigint", "as", "satisfies", "is",
            "infer", "override", "constructor",
        ], in: text, theme: theme, extraStrings: "`(?:\\\\.|[^`\\\\])*`")
        highlightPattern(#"@\w+"#, in: text, kind: .attribute, theme: theme)
    }

    /// Apple .strings files: "key" = "value"; with C-style comments.
    static func highlightStrings(in text: NSMutableAttributedString, theme: SyntaxTheme) {
        highlightPattern(#"//[^\n]*"#, in: text, kind: .comment, theme: theme)
        highlightPattern(#"/\*[\s\S]*?\*/"#, in: text, kind: .comment, theme: theme, options: [.dotMatchesLineSeparators])
        highlightPattern(#""(?:\\.|[^"\\])*""#, in: text, kind: .string, theme: theme)
        highlightPattern(#"(?m)^\s*"(?:\\.|[^"\\])*"(?=\s*=)"#, in: text, kind: .key, theme: theme)
        highlightPattern(#"(?m)^\s*[A-Za-z_][\w.]*(?=\s*=)"#, in: text, kind: .key, theme: theme)
        highlightPattern(#"[=;]"#, in: text, kind: .punctuation, theme: theme)
    }
}
