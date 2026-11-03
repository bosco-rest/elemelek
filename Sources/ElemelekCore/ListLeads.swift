import Foundation

/// Bold lead-ins for chat lists ("Źródło — nagłówek").
///
/// Detection works on two levels. An item has a lead when it opens with a short,
/// sentence-free label before ` — `, ` – `, ` | ` or `: `. The structure applies
/// to a list when short lists mostly share it (two thirds) or long mixed ones
/// carry a solid run of it (five and a third), so an occasional dash in prose
/// never restyles anything. Single paragraphs are never touched: on chat a dash
/// in a one-liner is almost always prose, not a label.
///
/// Detection runs on plain text (no Markdown syntax), and a lead is always a
/// prefix of the item, so rendering just marks that prefix strongly emphasized.
public enum ListLeads {
    public static let minimumItems = 3
    public static let minimumFraction = 2.0 / 3.0
    public static let maxLeadLength = 56

    private static let separators = [" — ", " – ", " | ", ": "]

    /// Length of the lead in characters, or nil when `text` does not open with one.
    public static func leadLength(in text: String) -> Int? {
        let hits = separators.compactMap { text.range(of: $0) }.sorted { $0.lowerBound < $1.lowerBound }
        for sep in hits {
            let lead = String(text[..<sep.lowerBound])
            let rest = String(text[sep.upperBound...])
            guard (2...maxLeadLength).contains(lead.count),
                  lead.rangeOfCharacter(from: .letters) != nil,
                  !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !lead.contains("!"), !lead.contains("?"),
                  !lead.contains(". "), !lead.hasSuffix(".")
            else { continue }
            return lead.count
        }
        return nil
    }

    /// A long mixed list still counts when a solid run of its items opens with a lead.
    public static let minimumHitsInLongList = 5
    public static let minimumFractionInLongList = 1.0 / 3.0

    /// Per-item lead lengths, parallel to `items`. All nil when the list as a
    /// whole does not follow the lead convention.
    public static func detect(in items: [String]) -> [Int?] {
        let empty = [Int?](repeating: nil, count: items.count)
        guard items.count >= minimumItems else { return empty }
        let leads = items.map(leadLength(in:))
        let hits = leads.compactMap { $0 }.count
        let fraction = Double(hits) / Double(items.count)
        // A short list where nearly every item opens with a label, or a long mixed
        // list with a solid run of them: both read as the same convention.
        let applies = (hits >= 2 && fraction >= minimumFraction)
            || (hits >= minimumHitsInLongList && fraction >= minimumFractionInLongList)
        guard applies else { return empty }
        return leads
    }
}
