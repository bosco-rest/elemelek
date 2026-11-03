import Foundation

/// What the room's thread list knows about one thread root.
public struct ThreadInfo: Equatable, Sendable {
    public var replies: Int
    public var latest: String?
    public init(replies: Int, latest: String?) { self.replies = replies; self.latest = latest }

    /// Reply count and newest reply for a root's chip: the event's own summary, filled in from the thread list
    /// where the list knows more or the event has no newest reply.
    public static func merge(replies: Int, latest: String?, with info: ThreadInfo?) -> (replies: Int, latest: String?) {
        guard let info else { return (replies, latest) }
        if info.replies > replies { return (info.replies, info.latest ?? latest) }
        if info.replies == replies, latest == nil { return (replies, info.latest) }
        return (replies, latest)
    }
}
