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
    /// The first batch from a listener is the timeline as it stands, not a change to it.
    public private(set) var seenFirstBatch = false

    public init() {}

    /// What one batch of diffs means for paging.
    public enum Batch: Equatable, Sendable {
        /// Nothing to do.
        case kept
        /// The SDK dropped what was loaded: page back again.
        case dropped
    }

    /// Reads one applied batch. `oldestBefore` is the oldest event's ID before the batch, `idsAfter` every event ID
    /// after it: a `reset` that still holds the oldest event is the same timeline sent again (a listener that fell
    /// behind), one that lost it was cut down to its newest events. A `clear` is always a drop.
    public mutating func received(_ out: ListDiffOutcome, oldestBefore: String?, idsAfter: Set<String>) -> Batch {
        guard seenFirstBatch else { seenFirstBatch = true; return .kept }
        let lostOldest = oldestBefore.map { !idsAfter.contains($0) } ?? false
        guard out.cleared || (out.reset && lostOldest) else { return .kept }
        epoch += 1
        hitStart = false
        return .dropped
    }

    /// A new listener on the same timeline: its first batch is the whole timeline again.
    public mutating func relisten() { seenFirstBatch = false }

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
