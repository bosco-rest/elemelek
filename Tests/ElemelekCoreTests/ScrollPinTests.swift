import Testing
@testable import ElemelekCore

struct ScrollPinTests {
    typealias G = ScrollPin.Geometry

    @Test func atBottomWithinTolerance() {
        #expect(G(offsetY: 500, contentHeight: 1000, viewportHeight: 500).isAtBottom)
        #expect(G(offsetY: 470, contentHeight: 1000, viewportHeight: 500).isAtBottom)
        #expect(!G(offsetY: 300, contentHeight: 1000, viewportHeight: 500).isAtBottom)
    }

    @Test func shortContentIsAtBottom() {
        #expect(G(offsetY: 0, contentHeight: 200, viewportHeight: 500).isAtBottom)
    }

    @Test func newMessageKeepsPinWhenAtBottom() {
        let old = G(offsetY: 500, contentHeight: 1000, viewportHeight: 500)
        let new = G(offsetY: 500, contentHeight: 1080, viewportHeight: 500)
        #expect(ScrollPin.next(wasPinned: true, old: old, new: new))
    }

    @Test func newMessageDoesNotPinReaderUpInHistory() {
        let old = G(offsetY: 100, contentHeight: 1000, viewportHeight: 500)
        let new = G(offsetY: 100, contentHeight: 1080, viewportHeight: 500)
        #expect(!ScrollPin.next(wasPinned: false, old: old, new: new))
    }

    @Test func scrollingFollowsPosition() {
        let bottom = G(offsetY: 500, contentHeight: 1000, viewportHeight: 500)
        let up = G(offsetY: 200, contentHeight: 1000, viewportHeight: 500)
        #expect(!ScrollPin.next(wasPinned: true, old: bottom, new: up))
        #expect(ScrollPin.next(wasPinned: false, old: up, new: bottom))
    }

    @Test func anchoredGrowthAtBottomStaysPinned() {
        let old = G(offsetY: 500, contentHeight: 1000, viewportHeight: 500)
        let new = G(offsetY: 580, contentHeight: 1080, viewportHeight: 500)
        #expect(ScrollPin.next(wasPinned: true, old: old, new: new))
    }

    @Test func newMessageWhileReadingHistoryDoesNotPin() {
        let old = G(offsetY: 100, contentHeight: 1000, viewportHeight: 500)
        #expect(!ScrollPin.next(wasPinned: false, old: old, new: G(offsetY: 100, contentHeight: 1080, viewportHeight: 500)))
        #expect(!ScrollPin.next(wasPinned: false, old: old, new: G(offsetY: 180, contentHeight: 1080, viewportHeight: 500)))
    }

    @Test func animationFrameOnTheWayDownStaysPinned() {
        let old = G(offsetY: 400, contentHeight: 1080, viewportHeight: 500)
        let mid = G(offsetY: 450, contentHeight: 1080, viewportHeight: 500)
        #expect(!mid.isAtBottom)
        #expect(ScrollPin.next(wasPinned: true, old: old, new: mid))
    }

    @Test func toleranceScalesWithZoom() {
        let g = G(offsetY: 440, contentHeight: 1000, viewportHeight: 500, zoom: 2)
        #expect(g.isAtBottom)
        #expect(!G(offsetY: 440, contentHeight: 1000, viewportHeight: 500).isAtBottom)
    }
}
