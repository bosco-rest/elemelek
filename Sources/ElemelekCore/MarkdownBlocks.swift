import Foundation

/// The block structure of a markdown text: headings, lists, checkboxes, code, quotes, tables, paragraphs.
/// Pure parsing, no view; the message renderer draws from it.
/// Inline (bold, `code`, links) stays for the renderer; `AttributedString(markdown:)` does it.
public enum MarkdownBlocks {
    /// A table column's alignment, as the `|---|:---:|---:|` row spells it.
    public enum Align: Sendable, Equatable {
        case leading, center, trailing
    }

    /// One item of a list: where it was written, how deep, its marker and its words. A numbered item carries the
    /// number it shows — the first of its run as written, then counted on, so a sub-list between two items does not
    /// start the count again.
    public struct Item: Equatable, Sendable {
        public enum Mark: Equatable, Sendable {
            case bullet
            case number(Int)
            case check(Bool)

            var ordered: Bool { if case .number = self { true } else { false } }
        }

        public let line: Int
        /// 0 for the list's own items, 1 for a sub-list under one of them, and so on.
        public let depth: Int
        public let mark: Mark
        public var text: String

        public init(line: Int, depth: Int = 0, mark: Mark, text: String) {
            self.line = line
            self.depth = depth
            self.mark = mark
            self.text = text
        }

        public var checked: Bool? { if case .check(let c) = mark { c } else { nil } }
    }

    public enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        /// Bullets, numbers and checkboxes, with the sub-lists under them: one block, so the numbers of the outer
        /// list run on across the sub-lists and the gaps inside stay an item's gap, not a block's.
        case list([Item])
        case code(String)
        case quote(String)
        case table(header: [String], align: [Align], rows: [[String]])
        case rule
    }

    public static func parse(_ text: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        var code: [String]?
        var list = ListBuilder()
        var quote: [String] = []
        var table: [String] = []
        /// A blank line inside a list: the list goes on if an item or an indented line follows, else it ends there.
        var blank = false

        func flushTable() {
            guard !table.isEmpty else { return }
            if let t = Table.parse(table) {
                out.append(.table(header: t.header, align: t.align, rows: t.rows))
            } else {
                // Pipes that are not a table are ordinary prose; they must not vanish.
                para.append(contentsOf: table)
            }
            table = []
        }

        func flush() {
            flushTable()
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] }
            if !list.items.isEmpty { out.append(.list(list.items)); list = ListBuilder() }
            if !quote.isEmpty { out.append(.quote(quote.joined(separator: "\n"))); quote = [] }
            blank = false
        }

        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if var c = code {
                if line.hasPrefix("```") {
                    out.append(.code(c.joined(separator: "\n"))); code = nil
                } else {
                    c.append(raw); code = c
                }
                continue
            }
            if line.isEmpty {
                if list.items.isEmpty { flush() } else { blank = true }
                continue
            }
            let indent = Self.indent(raw)
            let marker = listMarker(line)
            if blank, marker == nil, indent < 2 { flush() }
            if line.hasPrefix("```") { flush(); code = []; continue }
            if line == "---" || line == "***" { flush(); out.append(.rule); continue }
            if let h = line.prefix(while: { $0 == "#" }).count as Int?, h > 0, h <= 6, line.dropFirst(h).hasPrefix(" ")
            {
                flush()
                out.append(.heading(level: h, text: String(line.dropFirst(h + 1))))
                continue
            }
            // A table row: the model writes one row per line, and a paragraph that swallowed them reads as
            // a hedge of pipes (D34). Collected here, decided on at the flush.
            if Table.looksLikeRow(line) {
                if !list.items.isEmpty || !quote.isEmpty || !para.isEmpty { flush() }
                table.append(line)
                continue
            }
            flushTable()
            if let m = marker {
                if !para.isEmpty || !quote.isEmpty { flush() }
                // Numbers after bullets (or the reverse) at the outer level are two lists, as on the phone.
                if list.startsNew(indent: indent, ordered: m.mark.ordered) { flush() }
                list.add(line: i, indent: indent, mark: m.mark, text: m.text)
                blank = false
                continue
            }
            if line.hasPrefix("> ") {
                if !list.items.isEmpty || !para.isEmpty { flush() }
                quote.append(String(line.dropFirst(2)))
                continue
            }
            // List item continuation (indent) — append to the last item.
            if indent >= 2, !list.items.isEmpty {
                list.items[list.items.count - 1].text += " " + line
                blank = false
                continue
            }
            if !list.items.isEmpty || !quote.isEmpty { flush() }
            para.append(line)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }

    /// Leading whitespace in columns, a tab counted as four.
    static func indent(_ raw: String) -> Int {
        var n = 0
        for ch in raw {
            if ch == " " { n += 1 } else if ch == "\t" { n += 4 } else { break }
        }
        return n
    }

    /// A list item's marker (`- `, `* `, `+ `, `1. `, `1) `, `- [ ] `) and its words; nil for any other line.
    static func listMarker(_ line: String) -> (mark: Item.Mark, text: String)? {
        if let box = checkbox(line) { return (.check(box.checked), box.text) }
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return (.bullet, String(line.dropFirst(2)))
        }
        if line == "-" || line == "*" { return (.bullet, "") }
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 9, let n = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (.number(n), String(rest.dropFirst(2)))
    }

    /// The items of one list as they come, each put at its depth by its indent. An item indented past its
    /// predecessor's marker is under it; one at or left of an outer item's marker is that item's sibling. Lenient
    /// on purpose: models indent a sub-list under `1.` by two spaces as often as by three.
    struct ListBuilder {
        var items: [Item] = []
        /// The open levels, outermost first: where the marker stood, and the last number counted there.
        private var levels: [(indent: Int, ordered: Bool, number: Int?)] = []

        func startsNew(indent: Int, ordered: Bool) -> Bool {
            guard let outer = levels.first else { return false }
            return indent <= outer.indent && outer.ordered != ordered
        }

        mutating func add(line: Int, indent: Int, mark: Item.Mark, text: String) {
            while let last = levels.last, indent < last.indent, levels.count > 1 { levels.removeLast() }
            if let last = levels.last, indent >= last.indent + 2 {
                levels.append((indent, mark.ordered, nil))
            } else if levels.isEmpty {
                levels.append((indent, mark.ordered, nil))
            } else if levels[levels.count - 1].ordered != mark.ordered {
                // A different kind at the same depth starts its own count.
                levels[levels.count - 1] = (levels[levels.count - 1].indent, mark.ordered, nil)
            }
            var mark = mark
            if case .number(let written) = mark {
                let n = levels[levels.count - 1].number.map { $0 + 1 } ?? written
                levels[levels.count - 1].number = n
                mark = .number(n)
            }
            items.append(Item(line: line, depth: levels.count - 1, mark: mark, text: text))
        }
    }

    public static func checkbox(_ line: String) -> (checked: Bool, text: String)? {
        for (prefix, checked) in [
            ("- [ ] ", false), ("- [x] ", true), ("- [X] ", true), ("* [ ] ", false), ("* [x] ", true),
        ] {
            if line.hasPrefix(prefix) { return (checked, String(line.dropFirst(prefix.count))) }
        }
        if line == "- [ ]" || line == "- [x]" { return (line == "- [x]", "") }
        return nil
    }

    /// Toggles the checkbox on line `line`; returns the new text (nil when it isn't a checkbox).
    public static func toggle(_ text: String, line: Int) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return nil }
        let raw = lines[line]
        let indent = raw.prefix { $0 == " " || $0 == "\t" }
        let body = raw.dropFirst(indent.count)
        guard let box = checkbox(String(body)) else { return nil }
        let marker = body.hasPrefix("*") ? "*" : "-"
        lines[line] = indent + "\(marker) [\(box.checked ? " " : "x")]" + (box.text.isEmpty ? "" : " " + box.text)
        return lines.joined(separator: "\n")
    }

    /// GitHub-flavoured tables. A pipe line on its own is not a table: it takes a header, a `|---|` row under it,
    /// and at least that. Anything short of it goes back to being prose.
    public enum Table {
        /// A line that could belong to a table: it starts with a pipe, or carries one that is not escaped.
        public static func looksLikeRow(_ line: String) -> Bool {
            guard line.hasPrefix("|") else { return false }
            return !cells(line).isEmpty
        }

        /// The `|---|:--:|` row: every cell is dashes, with optional colons at the ends.
        public static func alignments(_ line: String) -> [Align]? {
            let cells = cells(line)
            guard !cells.isEmpty else { return nil }
            var out: [Align] = []
            for c in cells {
                let left = c.hasPrefix(":")
                let right = c.hasSuffix(":")
                let dashes = c.dropFirst(left ? 1 : 0).dropLast(right && c.count > 1 ? 1 : 0)
                guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
                out.append(left && right ? .center : right ? .trailing : .leading)
            }
            return out
        }

        public static func parse(_ lines: [String]) -> (header: [String], align: [Align], rows: [[String]])? {
            guard lines.count >= 2, let align = alignments(lines[1]) else { return nil }
            let header = cells(lines[0])
            guard header.count == align.count else { return nil }
            // A short row is padded, a long one keeps its extra cells: a half-written table still shows.
            let rows = lines.dropFirst(2).map { row -> [String] in
                var c = cells(row)
                while c.count < header.count { c.append("") }
                return c
            }
            return (header, align, rows)
        }

        /// Cells of one row: split on unescaped pipes, the outer ones dropped.
        public static func cells(_ line: String) -> [String] {
            var out: [String] = []
            var cur = ""
            var it = line.makeIterator()
            while let ch = it.next() {
                if ch == "\\" {
                    // `\|` is a pipe inside a cell, not a separator; every other escape stays as written.
                    if let next = it.next() {
                        cur.append(next == "|" ? "|" : "\\")
                        if next != "|" { cur.append(next) }
                    } else {
                        cur.append("\\")
                    }
                    continue
                }
                if ch == "|" {
                    out.append(cur)
                    cur = ""
                    continue
                }
                cur.append(ch)
            }
            out.append(cur)
            if out.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeFirst() }
            if out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast() }
            return out.map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }
}
