import Foundation

/// A small syntax highlighter for code blocks: JSON and common languages, by
/// token, not by grammar. It only colours; a wrong guess costs a colour, never text. Pure: the view only maps
/// a kind to a colour.
public enum Syntax {
    public enum Language: String, Sendable, CaseIterable {
        case json, swift, c, go, rust, javascript, php, python, shell, yaml, toml, sql, plain
    }

    public enum Kind: Sendable, Equatable {
        case keyword, string, number, comment, key, literal
    }

    public struct Token: Sendable, Equatable {
        /// UTF-16 offsets into the text, so the app can lay them onto an `NSString`/`AttributedString` range.
        public let start: Int
        public let length: Int
        public let kind: Kind
    }

    /// The language by the file's name; nil when it is not something to read as text here (a picture, a binary).
    public static func language(forPath path: String) -> Language? {
        let name = (path as NSString).lastPathComponent.lowercased()
        if name == "makefile" || name == "dockerfile" { return .shell }
        if [".gitignore", ".env", "license", "readme"].contains(name) { return .plain }
        switch (name as NSString).pathExtension {
        case "json", "jsonl", "geojson", "jsonc": return .json
        case "swift": return .swift
        case "c", "h", "m", "mm", "cpp", "hpp", "cc", "java", "kt", "cs": return .c
        case "go": return .go
        case "rs": return .rust
        case "js", "mjs", "cjs", "jsx", "ts", "tsx": return .javascript
        case "php": return .php
        case "py": return .python
        case "sh", "bash", "zsh", "fish": return .shell
        case "yml", "yaml": return .yaml
        case "toml", "ini", "cfg", "conf": return .toml
        case "sql": return .sql
        case "txt", "log", "csv", "tsv", "xml", "html", "css", "plist", "strings", "diff", "patch": return .plain
        default: return nil
        }
    }

    /// Minified JSON (one long line) made readable. Only the whitespace between tokens changes — numbers and key
    /// order stay as written, which a parse and re-encode would not keep. Anything else comes back as is.
    public static func prettyJSON(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count <= 2, text.utf8.count > 120, let data = text.data(using: .utf8),
            (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
        else { return text }
        var out = ""
        var depth = 0
        var inString = false
        var escaped = false
        let chars = Array(text)
        func newline() { out += "\n" + String(repeating: "  ", count: depth) }
        for (i, c) in chars.enumerated() {
            if inString {
                out.append(c)
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
                continue
            }
            switch c {
            case "\"": inString = true; out.append(c)
            case "{", "[":
                out.append(c)
                // An empty object or array stays `{}`.
                let next = chars[(i + 1)...].first { !$0.isWhitespace }
                depth += 1
                if next != "}" && next != "]" { newline() }
            case "}", "]":
                depth -= 1
                if let last = out.last, last != "{" && last != "[" { newline() }
                out.append(c)
            case ",": out.append(c); newline()
            case ":": out += ": "
            case " ", "\t", "\n", "\r": break
            default: out.append(c)
            }
        }
        return out + "\n"
    }

    /// A code block with no language named: JSON when it looks like it, otherwise nothing is guessed.
    public static func guess(_ code: String) -> Language {
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = t.first, let l = t.last, (f == "{" && l == "}") || (f == "[" && l == "]") { return .json }
        return .plain
    }

    public static func tokens(_ text: String, _ lang: Language) -> [Token] {
        guard lang != .plain else { return [] }
        let s = Array(text.utf16)
        var out: [Token] = []
        var i = 0
        let words = keywords[lang] ?? []
        let hashComment = [.python, .shell, .yaml, .toml, .php].contains(lang)
        let slashComment = [.swift, .c, .go, .rust, .javascript, .json, .php].contains(lang)
        func at(_ k: Int) -> UInt16 { k < s.count ? s[k] : 0 }
        func isIdent(_ c: UInt16) -> Bool {
            (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127
        }
        var lineStart = true
        while i < s.count {
            let c = s[i]
            if c == 10 { lineStart = true; i += 1; continue }
            if c == 32 || c == 9 { i += 1; continue }
            let startsLine = lineStart
            lineStart = false
            // Comments to the end of the line.
            if (hashComment && c == 35) || (slashComment && c == 47 && at(i + 1) == 47)
                || (lang == .sql && c == 45 && at(i + 1) == 45)
            {
                let st = i
                while i < s.count, s[i] != 10 { i += 1 }
                out.append(Token(start: st, length: i - st, kind: .comment))
                continue
            }
            if slashComment && c == 47 && at(i + 1) == 42 {
                let st = i
                i += 2
                while i < s.count, !(s[i] == 42 && at(i + 1) == 47) { i += 1 }
                i = min(s.count, i + 2)
                out.append(Token(start: st, length: i - st, kind: .comment))
                continue
            }
            // Strings; in JSON a string followed by `:` is a key.
            if c == 34 || c == 39 || (c == 96 && lang == .javascript) {
                if c == 39 && (lang == .rust || lang == .json) { i += 1; continue }
                let st = i
                i += 1
                while i < s.count, s[i] != c {
                    if s[i] == 92 { i += 2; continue }
                    if s[i] == 10 && c != 96 && lang != .python { break }
                    i += 1
                }
                i = min(s.count, i)
                if i < s.count, s[i] == c { i += 1 }
                var k = i
                while k < s.count, s[k] == 32 || s[k] == 9 { k += 1 }
                let isKey = lang == .json && at(k) == 58
                out.append(Token(start: st, length: i - st, kind: isKey ? .key : .string))
                continue
            }
            if (c >= 48 && c <= 57) || (c == 45 && lang == .json && at(i + 1) >= 48 && at(i + 1) <= 57) {
                let st = i
                i += 1
                while i < s.count, isIdent(s[i]) || s[i] == 46 || ((s[i] == 43 || s[i] == 45) && (s[i - 1] | 32) == 101)
                {
                    i += 1
                }
                out.append(Token(start: st, length: i - st, kind: .number))
                continue
            }
            if isIdent(c) {
                let st = i
                while i < s.count, isIdent(s[i]) || ((lang == .yaml || lang == .toml) && (s[i] == 45 || s[i] == 46)) {
                    i += 1
                }
                let word = String(decoding: s[st..<i], as: UTF16.self)
                var k = i
                while k < s.count, s[k] == 32 || s[k] == 9 { k += 1 }
                if lang == .php && s[st] == 36 {
                    out.append(Token(start: st, length: i - st, kind: .key))  // `$name`
                } else if (lang == .yaml && at(k) == 58) || (lang == .toml && startsLine && at(k) == 61) {
                    out.append(Token(start: st, length: i - st, kind: .key))
                } else if literals.contains(lang == .sql ? word.lowercased() : word) {
                    out.append(Token(start: st, length: i - st, kind: .literal))
                } else if words.contains(lang == .sql ? word.lowercased() : word) {
                    out.append(Token(start: st, length: i - st, kind: .keyword))
                }
                continue
            }
            i += 1
        }
        return out
    }

    private static let literals: Set<String> = [
        "true", "false", "null", "nil", "None", "True", "False", "undefined", "self", "Self", "this", "yes", "no",
    ]

    private static let keywords: [Language: Set<String>] = [
        .swift: [
            "func", "let", "var", "if", "else", "guard", "return", "struct", "enum", "class", "protocol", "extension",
            "import", "for", "in", "while", "switch", "case", "default", "break", "continue", "static", "private",
            "public", "internal", "fileprivate", "final", "init", "throws", "throw", "try", "await", "async", "actor",
            "some", "any", "where", "defer", "do", "catch", "typealias", "mutating", "inout", "override", "lazy",
            "weak",
        ],
        .c: [
            "int", "char", "void", "return", "if", "else", "for", "while", "do", "switch", "case", "default", "break",
            "continue", "struct", "typedef", "static", "const", "unsigned", "long", "short", "double", "float", "enum",
            "class", "public", "private", "protected", "new", "delete", "include", "define", "import", "package",
            "namespace", "using", "virtual", "template", "fun", "val", "var", "sizeof", "extern", "boolean",
        ],
        .go: [
            "func", "package", "import", "var", "const", "type", "struct", "interface", "map", "chan", "go", "defer",
            "return", "if", "else", "for", "range", "switch", "case", "default", "break", "continue", "select",
        ],
        .rust: [
            "fn", "let", "mut", "pub", "use", "mod", "struct", "enum", "impl", "trait", "for", "in", "if", "else",
            "match", "return", "while", "loop", "break", "continue", "const", "static", "where", "async", "await",
            "move", "ref", "dyn", "crate", "super", "unsafe", "type", "as",
        ],
        .php: [
            "function", "fn", "return", "if", "else", "elseif", "foreach", "for", "while", "as", "echo", "print",
            "class", "new", "public", "private", "protected", "static", "use", "namespace", "require", "require_once",
            "include", "array", "try", "catch", "throw", "match", "switch", "case", "default", "break", "continue",
            "const", "declare", "php",
        ],
        .javascript: [
            "function", "const", "let", "var", "return", "if", "else", "for", "while", "do", "switch", "case",
            "default", "break", "continue", "class", "extends", "new", "import", "export", "from", "async", "await",
            "try", "catch", "finally", "throw", "typeof", "instanceof", "of", "in", "interface", "type", "enum",
            "implements", "private", "public", "readonly", "static", "as",
        ],
        .python: [
            "def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or", "is", "import",
            "from", "as", "with", "try", "except", "finally", "raise", "lambda", "yield", "pass", "break", "continue",
            "global", "async", "await",
        ],
        .shell: [
            "if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "case", "esac", "function",
            "return", "export", "local", "set", "echo", "exit",
        ],
        .sql: [
            "select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete",
            "create", "table", "index", "on", "join", "left", "inner", "group", "by", "order", "limit", "as", "primary",
            "key", "integer", "text", "if", "exists", "drop", "alter", "add", "default",
        ],
    ]
}
