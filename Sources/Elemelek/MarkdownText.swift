import SwiftUI
import ElemelekCore

/// Chat markdown, set for reading: a reading measure, not decoration. Blocks come from
/// `MarkdownBlocks.parse` (headings, lists with sub-lists, quotes, fenced code, tables); inline styles and links
/// go through `AttributedString(markdown:)`.
enum MarkdownMetrics {
    static let leading: CGFloat = 5
    static let blockSpacing: CGFloat = 10
    static let headingSpace: CGFloat = 12
    static let itemSpacing: CGFloat = 7

    static func markerWidth(_ m: MarkdownBlocks.Item.Mark) -> CGFloat {
        switch m {
        case .bullet: 18
        case .number: 26
        case .check: 20
        }
    }

    /// How far each item stands in: a sub-list's marker under the words of the item it belongs to.
    static func listOffsets(_ items: [MarkdownBlocks.Item]) -> [CGFloat] {
        var starts: [CGFloat] = [0]
        return items.map { it in
            while starts.count <= it.depth { starts.append(starts.last ?? 0) }
            let at = starts[it.depth]
            starts = Array(starts.prefix(it.depth + 1)) + [at + markerWidth(it.mark)]
            return at
        }
    }
}

struct MarkdownText: View {
    @Environment(\.zoomFactor) var zoom
    let text: String
    var size: CGFloat = 14

    /// Follows the system's text size; 1.0 at the default setting, a no-op where unsupported.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    /// Every prose measure below derives from this, so larger text stays proportional.
    private var scaled: CGFloat { size * unit }

    private var body_: Font { Theme.font(size: zoom * scaled) }

    var body: some View {
        let blocks = MarkdownCache.blocks(text)
        // One pool for the whole message: a digest's convention ("source — headline")
        // spans its sections, and sections alone are too small to judge.
        let leads = leadMap(blocks: blocks)
        VStack(alignment: .leading, spacing: MarkdownMetrics.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in block(b, first: i == 0, leads: leads) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    /// Lead lengths by the source line of their item; only qualifying items are present.
    private func leadMap(blocks: [MarkdownBlocks.Block]) -> [Int: Int] {
        var lines: [Int] = []
        var plains: [String] = []
        for b in blocks {
            guard case .list(let items) = b else { continue }
            for it in items {
                lines.append(it.line)
                plains.append(String(MarkdownCache.inline(it.text, size: scaled).characters))
            }
        }
        let lens = ListLeads.detect(in: plains)
        return Dictionary(uniqueKeysWithValues: zip(lines, lens).compactMap { line, len in len.map { (line, $0) } })
    }

    @ViewBuilder private func block(_ b: MarkdownBlocks.Block, first: Bool, leads: [Int: Int] = [:]) -> some View {
        switch b {
        case .heading(let level, let t):
            inline(t)
                .font(Theme.font(size: zoom * (level == 1 ? scaled + 4 : level == 2 ? scaled + 2 : scaled), weight: level <= 2 ? .bold : .semibold))
                .foregroundStyle(Theme.text)
                .padding(.top, first ? 0 : level <= 2 ? MarkdownMetrics.headingSpace : 4)
        case .paragraph(let t):
            if SectionHeader.isHeader(String(MarkdownCache.inline(t, size: scaled).characters)) {
                inline(t).font(Theme.font(size: zoom * scaled, weight: .semibold)).foregroundStyle(Theme.text).lineSpacing(MarkdownMetrics.leading)
            } else {
                inline(t).font(body_).foregroundStyle(Theme.text).lineSpacing(MarkdownMetrics.leading)
            }
        case .list(let items):
            let offsets = MarkdownMetrics.listOffsets(items)
            VStack(alignment: .leading, spacing: MarkdownMetrics.itemSpacing) {
                ForEach(Array(items.enumerated()), id: \.element.line) { i, it in
                    listItem(it, lead: leads[it.line] ?? nil).padding(.leading, offsets[i])
                }
            }
        case .code(let c):
            Text(CodeHighlight.text(c, Syntax.guess(c)))
                .font(Theme.font(size: zoom * (scaled - 2.5), design: .monospaced))
                .foregroundStyle(Theme.text).lineSpacing(2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading).sunken()
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline))
        case .quote(let q):
            HStack(spacing: 10) {
                Rectangle().fill(Theme.edge).frame(width: 2)
                inline(q).font(body_).foregroundStyle(Theme.dim).lineSpacing(MarkdownMetrics.leading)
            }
        case .table(let header, let align, let rows):
            MarkdownTable(header: header, align: align, rows: rows, inline: inline)
        case .rule:
            Rectangle().fill(Theme.edge).frame(height: 1)
        }
    }

    @ViewBuilder private func listItem(_ it: MarkdownBlocks.Item, lead: Int?) -> some View {
        switch it.mark {
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Theme.dim).frame(width: 10, alignment: .leading)
                leadInline(it.text, lead: lead).font(body_).foregroundStyle(Theme.text).lineSpacing(MarkdownMetrics.leading)
            }
        case .number(let n):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).").font(body_).monospacedDigit().foregroundStyle(Theme.dim)
                    .frame(minWidth: 18, alignment: .trailing)
                leadInline(it.text, lead: lead).font(body_).foregroundStyle(Theme.text).lineSpacing(MarkdownMetrics.leading)
            }
        case .check(let checked):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(checked ? "☑︎" : "☐").foregroundStyle(checked ? Theme.green : Theme.dim)
                leadInline(it.text.isEmpty ? "…" : it.text, lead: lead).font(body_)
                    .foregroundStyle(checked ? Theme.dim : Theme.text)
                    .strikethrough(checked, color: Theme.dim)
            }
        }
    }

    private func inline(_ s: String) -> Text { Text(MarkdownCache.inline(s, size: scaled)) }

    /// The item's text with its lead in semibold — calm at this density, where bold
    /// would shout. Links inside keep their colour and gain the weight; code keeps
    /// its monospace face.
    private func leadInline(_ s: String, lead: Int?) -> Text {
        var a = MarkdownCache.inline(s, size: scaled)
        if let n = lead, n > 0 {
            let plain = String(a.characters)
            if plain.count >= n, let end = plain.index(plain.startIndex, offsetBy: n, limitedBy: plain.endIndex) {
                let lo = a.startIndex
                let hi = a.characters.index(lo, offsetBy: plain.distance(from: plain.startIndex, to: end))
                let targets = a.runs.compactMap { run -> (Range<AttributedString.Index>, Bool)? in
                    guard run.range.lowerBound >= lo, run.range.upperBound <= hi else { return nil }
                    return (run.range, run.inlinePresentationIntent?.contains(.code) == true)
                }
                for (range, coded) in targets {
                    a[range].font = coded
                        ? Theme.font(size: zoom * (scaled - 1.5), weight: .semibold, design: .monospaced)
                        : Theme.font(size: zoom * scaled, weight: .semibold)
                }
            }
        }
        return Text(a)
    }
}

private struct MarkdownTable: View {
    @Environment(\.zoomFactor) var zoom
    let header: [String]
    let align: [MarkdownBlocks.Align]
    let rows: [[String]]
    let inline: (String) -> Text

    private var columns: Int { max(header.count, rows.map(\.count).max() ?? 0) }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<columns, id: \.self) { c in cell(header.indices.contains(c) ? header[c] : "", column: c, header: true) }
            }
            .background(Theme.wash(0.05))
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                Rectangle().fill(Theme.hairline).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in cell(row.indices.contains(c) ? row[c] : "", column: c, header: false) }
                }
                .background(i.isMultiple(of: 2) ? Color.clear : Theme.wash(0.02))
            }
        }
        .background(Theme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cell(_ text: String, column: Int, header: Bool) -> some View {
        let a = align.indices.contains(column) ? align[column] : .leading
        return inline(text)
            .font(Theme.font(size: zoom * 12.5, weight: header ? .semibold : .regular))
            .foregroundStyle(header ? Theme.text : Theme.text)
            .lineSpacing(2)
            .multilineTextAlignment(a == .trailing ? .trailing : a == .center ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: a == .trailing ? .trailing : a == .center ? .center : .leading)
    }
}

/// Parsed blocks and styled inline text, kept by their source: a chat's rows are drawn again on every update.
@MainActor enum MarkdownCache {
    private static var parsed: [String: [MarkdownBlocks.Block]] = [:]
    private static var styled: [String: AttributedString] = [:]

    static func blocks(_ text: String) -> [MarkdownBlocks.Block] {
        if let hit = parsed[text] { return hit }
        if parsed.count > 2000 { parsed.removeAll() }
        let b = MarkdownBlocks.parse(text)
        parsed[text] = b
        return b
    }

    static func inline(_ s: String, size: CGFloat) -> AttributedString {
        let key = "\(size)\n" + s
        if let hit = styled[key] { return hit }
        if styled.count > 4000 { styled.removeAll() }
        var a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        // `code` inside a sentence: a size down, tinted, on a wash.
        for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
            a[run.range].font = .system(size: size - 1.5, design: .monospaced)
            a[run.range].foregroundColor = Theme.orange
            a[run.range].backgroundColor = Theme.wash(0.08)
        }
        // Bare URLs become links as well.
        let plain = String(a.characters)
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for m in det.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                guard let url = m.url, let r = Range(m.range, in: plain) else { continue }
                let lo = a.characters.index(a.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: r.lowerBound))
                let hi = a.characters.index(a.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: r.upperBound))
                if a[lo..<hi].link == nil { a[lo..<hi].link = url }
            }
        }
        for run in a.runs where run.link != nil {
            // Links read by colour alone; a permanent underline would shout over the headlines.
            a[run.range].foregroundColor = Theme.accent
            a[run.range].underlineStyle = NSUnderlineStyle(rawValue: 0)
        }
        styled[key] = a
        return a
    }
}

/// `Syntax.tokens` in colours: keys blue, strings green, numbers orange, keywords the accent, comments dimmed.
@MainActor enum CodeHighlight {
    static func text(_ code: String, _ lang: Syntax.Language) -> AttributedString {
        guard lang != .plain else { return AttributedString(code) }
        let u = code.utf16
        var out = AttributedString()
        var at = 0
        func piece(_ from: Int, _ to: Int) -> Substring {
            code[String.Index(utf16Offset: from, in: code)..<String.Index(utf16Offset: to, in: code)]
        }
        for t in Syntax.tokens(code, lang) where t.start >= at && t.start + t.length <= u.count {
            if t.start > at { out += AttributedString(piece(at, t.start)) }
            var run = AttributedString(piece(t.start, t.start + t.length))
            run.foregroundColor = color(t.kind)
            out += run
            at = t.start + t.length
        }
        if at < u.count { out += AttributedString(piece(at, u.count)) }
        return out
    }

    private static func color(_ k: Syntax.Kind) -> Color {
        switch k {
        case .key: Theme.blueprint
        case .string: Theme.green
        case .number: Theme.orange
        case .literal, .keyword: Theme.accent
        case .comment: Theme.dim
        }
    }
}
