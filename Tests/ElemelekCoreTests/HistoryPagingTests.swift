import Testing
@testable import ElemelekCore

/// The case behind messages that never showed: a small room pages to its start, then a limited sync makes the SDK
/// drop the loaded timeline and keep only the newest events, with a gap before them. Each test feeds the diffs the
/// SDK sends, in order, through the same calls TimelineModel makes.
@Suite struct HistoryPagingTests {
    /// What TimelineModel keeps: the rows mirrored from the SDK and the paging state.
    struct Room {
        var rows: [String] = []
        var paging = HistoryPaging()

        mutating func receive(_ diffs: [ListDiff<String>]) -> HistoryPaging.Batch {
            let oldest = rows.first
            let out = rows.apply(diffs)
            return paging.received(out, oldestBefore: oldest, idsAfter: Set(rows))
        }

        /// A page that answers at once; returns whether it counted.
        mutating func page(hitStart: Bool) -> Bool {
            paging.finished(ticket: paging.ticket, hitStart: hitStart)
        }
    }

    @Test func theListenersFirstResetIsNotADrop() {
        var r = Room()
        let b1 = r.receive([.reset(["a", "b"])])
        #expect(b1 == .kept)
        #expect(r.paging.epoch == 0)
    }

    @Test func aLimitedSyncAfterTheRoomReachedItsStartPagesAgain() {
        var r = Room()
        let b2 = r.receive([.reset(["b", "c"])])
        #expect(b2 == .kept)
        _ = r.page(hitStart: true)
        let b3 = r.receive([.pushFront("a")])
        #expect(b3 == .kept)
        #expect(r.paging.hitStart)

        // Two new messages, d and e, arrive in one sync; the room list syncs one event per room, so the answer is
        // limited: the SDK clears the timeline and keeps only e. d sits in the gap.
        let b4 = r.receive([.clear, .append(["e"])])
        #expect(b4 == .dropped)
        #expect(r.rows == ["e"])
        #expect(!r.paging.hitStart, "a dropped timeline has a gap before it; paging must go on")

        // Paging back fills the gap: d shows.
        let b5 = r.receive([.pushFront("d"), .pushFront("c"), .pushFront("b"), .pushFront("a")])
        #expect(b5 == .kept)
        _ = r.page(hitStart: true)
        #expect(r.rows == ["a", "b", "c", "d", "e"])
        #expect(r.paging.hitStart)
    }

    @Test func aPageInFlightWhenTheTimelineDropsDoesNotMarkTheNewOneComplete() {
        var r = Room()
        _ = r.receive([.reset(["b", "c"])])
        let ticket = r.paging.ticket // a page is asked for

        let b6 = r.receive([.clear, .append(["e"])])
        #expect(b6 == .dropped)

        // It answers "start reached" for the old timeline: ignored, and the caller pages again.
        let stale = r.paging.finished(ticket: ticket, hitStart: true)
        #expect(!stale)
        #expect(!r.paging.hitStart)
        let b7 = r.page(hitStart: true)
        #expect(b7)
        #expect(r.paging.hitStart)
    }

    @Test func aResetThatKeepsTheOldestEventIsTheSameTimelineSentAgain() {
        // A listener that falls behind gets the whole state again as a reset: no gap, nothing to page.
        var r = Room()
        _ = r.receive([.reset(["a", "b"])])
        _ = r.page(hitStart: true)
        let b8 = r.receive([.reset(["a", "b", "c"])])
        #expect(b8 == .kept)
        #expect(r.paging.hitStart)
    }

    @Test func aResetThatLostTheOldestEventIsADrop() {
        var r = Room()
        _ = r.receive([.reset(["a", "b"])])
        _ = r.page(hitStart: true)
        let b9 = r.receive([.reset(["e"])])
        #expect(b9 == .dropped)
        #expect(!r.paging.hitStart)
    }

    @Test func aNewListenersFirstResetIsNotADrop() {
        // After our rows stopped matching the SDK the model listens again; that listener starts with a reset too.
        var r = Room()
        _ = r.receive([.reset(["a", "b"])])
        _ = r.page(hitStart: true)
        r.paging.relisten()
        let b10 = r.receive([.reset(["c"])])
        #expect(b10 == .kept)
        #expect(r.paging.hitStart)
    }

    @Test func ordinaryNewMessagesChangeNothing() {
        var r = Room()
        _ = r.receive([.reset(["a"])])
        _ = r.page(hitStart: true)
        let b11 = r.receive([.pushBack("b"), .set(0, "a2"), .remove(1)])
        #expect(b11 == .kept)
        #expect(r.paging.hitStart)
        #expect(r.paging.epoch == 0)
    }
}
