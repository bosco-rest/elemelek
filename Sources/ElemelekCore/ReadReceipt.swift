import Foundation

/// A read receipt indicating up to which message a user has read.
public struct ReadReceipt: Identifiable, Hashable, Sendable {
    public var id: String { userID }
    public let userID: String
    public var displayName: String
    public var avatarURL: String?
    public var date: Date?

    public init(userID: String, displayName: String, avatarURL: String? = nil, date: Date? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.date = date
    }
}

/// How read receipts are presented below messages in the timeline.
public enum ReadReceiptStyle: String, CaseIterable, Sendable {
    case avatarsAndNames = "avatarsAndNames"
    case avatarsOnly = "avatarsOnly"
    case namesOnly = "namesOnly"

    public static let key = "readReceiptStyle"
    public static let defaultValue: ReadReceiptStyle = .avatarsAndNames

    public var title: String {
        switch self {
        case .avatarsAndNames: "Avatars and names"
        case .avatarsOnly: "Avatars only"
        case .namesOnly: "Names only"
        }
    }
}

/// Formatter for read receipts summaries, labels, and hover tooltips.
public enum ReadReceiptFormatter {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// A concise label to display next to avatars (or by itself), e.g. "Read by Alice", "Read by Alice, Bob", or "Read by Alice, Bob +3".
    public static func summary(for receipts: [ReadReceipt], prefix: String = "Read by ") -> String {
        guard !receipts.isEmpty else { return "" }
        let names = receipts.map(\.displayName)
        switch names.count {
        case 1:
            return "\(prefix)\(names[0])"
        case 2:
            return "\(prefix)\(names[0]), \(names[1])"
        case 3:
            return "\(prefix)\(names[0]), \(names[1]), \(names[2])"
        default:
            let remaining = names.count - 2
            return "\(prefix)\(names[0]), \(names[1]) +\(remaining)"
        }
    }

    /// Label formatted according to the user's preferred style.
    public static func label(for receipts: [ReadReceipt], style: ReadReceiptStyle, prefix: String = "Read by ") -> String {
        switch style {
        case .avatarsOnly:
            return ""
        case .namesOnly, .avatarsAndNames:
            return summary(for: receipts, prefix: prefix)
        }
    }

    /// Full detailed tooltip for hover, e.g. "Read by Alice (10:45 AM), Bob (10:46 AM)".
    public static func tooltip(for receipts: [ReadReceipt], prefix: String = "Read by ") -> String {
        guard !receipts.isEmpty else { return "" }
        let items = receipts.map { r in
            if let date = r.date {
                return "\(r.displayName) (\(timeFormatter.string(from: date)))"
            }
            return r.displayName
        }
        return "\(prefix)\(items.joined(separator: ", "))"
    }
}
