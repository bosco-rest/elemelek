import Foundation

public enum LinkFinder {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The first few distinct web links of a message, in order.
    public static func all(in text: String, limit: Int = 3) -> [URL] {
        guard text.contains("http") else { return [] }
        let ns = text as NSString
        var out: [URL] = []
        for m in detector?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [] {
            if let u = m.url, ["http", "https"].contains(u.scheme?.lowercased()), !out.contains(u) { out.append(u) }
            if out.count == limit { break }
        }
        return out
    }
}
