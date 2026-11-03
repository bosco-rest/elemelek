import Foundation

/// Section labels inside a digest ("Zarchiwizowane (1):", "Warto zobaczyć teraz (2):").
/// A short single-line paragraph ending with a colon introduces what follows, so it
/// renders as a header instead of body text. Operates on plain text (no Markdown syntax).
public enum SectionHeader {
    public static let maxLength = 100

    public static func isHeader(_ paragraph: String) -> Bool {
        guard !paragraph.contains("\n") else { return false }
        let t = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...maxLength).contains(t.count), t.hasSuffix(":") else { return false }
        return true
    }
}
