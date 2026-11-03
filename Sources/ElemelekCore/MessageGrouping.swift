import Foundation

/// When a timeline message shows its header (avatar, sender, time).
///
/// Headers show by default. Grouping applies only when the previous message is
/// from the same sender (by ID, so two same-named people never merge; a rename
/// still breaks the group), close in time (5 minutes), and on the same day.
/// Anything else — another sender, a gap, midnight, missing or scrambled dates —
/// starts a new group with its header.
public protocol GroupedMessage: Sendable {
    var senderID: String { get }
    var senderName: String { get }
    var date: Date? { get }
}

public enum MessageGrouping {
    /// Two messages further apart than this never share a header.
    public static let maxGap: TimeInterval = 300

    public static func showsHeader<Row: GroupedMessage>(current: Row, previous: Row?) -> Bool {
        guard let prev = previous else { return true }
        if prev.senderID != current.senderID || prev.senderName != current.senderName { return true }
        guard let a = prev.date, let b = current.date, b >= a else { return true }
        if !Calendar.current.isDate(a, inSameDayAs: b) { return true }
        if b.timeIntervalSince(a) > maxGap { return true }
        return false
    }
}
