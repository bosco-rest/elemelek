/// Whether older messages are left to load, kept honest when the SDK throws away the timeline it had loaded.
///
/// The SDK does that when a sync comes back "limited" (more new events than it sent): it keeps only the newest
/// events and leaves a gap that only paging backwards fills. A room that had already reached its start would
/// otherwise stay marked as complete and never page again, so the gap — new messages among them — never shows.
public struct HistoryPaging: Equatable, Sendable {
    /// The room's first event is loaded; nothing older to ask for.
    public private(set) var hitStart = false
    /// Bumped each time the SDK drops the loaded timeline. A page asked for before then answered for a timeline
    /// that is gone, so its "start reached" says nothing about the new one.
    public private(set) var epoch = 0

    public init() {}

    /// The SDK replaced everything it had loaded (a `clear` or `reset` after the first batch).
    public mutating func dropped() {
        epoch += 1
        hitStart = false
    }

    /// Taken when a page is asked for, handed back to `finished`.
    public var ticket: Int { epoch }

    /// Records a page's answer. Returns false when the timeline was dropped meanwhile: the answer is ignored and
    /// the caller should page again to fill the new timeline.
    @discardableResult
    public mutating func finished(ticket: Int, hitStart: Bool) -> Bool {
        guard ticket == epoch else { return false }
        self.hitStart = hitStart
        return true
    }
}
