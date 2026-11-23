import Testing
@testable import ElemelekCore

/// The case behind messages that never showed: a small room pages to its start, then a limited sync makes the SDK
/// drop the loaded timeline and keep only the newest events, with a gap before them.
@Suite struct HistoryPagingTests {
    @Test func aRoomThatReachedItsStartPagesAgainAfterTheSDKDropsTheTimeline() {
        var p = HistoryPaging()
        let counted = p.finished(ticket: p.ticket, hitStart: true)
        #expect(counted)
        #expect(p.hitStart)

        // The SDK sends `clear` + the newest events: what was loaded, and the messages in between, are gone.
        var rows = ["a", "b", "c"]
        let out = rows.apply([.clear, .append(["e"])])
        #expect(out.dropped)
        p.dropped()

        #expect(!p.hitStart, "a dropped timeline has a gap before it; paging must go on")
        #expect(rows == ["e"])
    }

    @Test func aPageThatWasInFlightWhenTheTimelineDroppedDoesNotMarkTheNewOneComplete() {
        var p = HistoryPaging()
        let ticket = p.ticket
        p.dropped()
        let stale = p.finished(ticket: ticket, hitStart: true)
        #expect(!stale, "the answer belongs to the old timeline")
        #expect(!p.hitStart)

        // The next page, asked for the new timeline, counts.
        let fresh = p.finished(ticket: p.ticket, hitStart: true)
        #expect(fresh)
        #expect(p.hitStart)
    }

    @Test func aFailedOrUnfinishedPageLeavesTheStateAlone() {
        var p = HistoryPaging()
        let counted = p.finished(ticket: p.ticket, hitStart: false)
        #expect(counted)
        #expect(!p.hitStart)
        #expect(p.epoch == 0)
    }
}
