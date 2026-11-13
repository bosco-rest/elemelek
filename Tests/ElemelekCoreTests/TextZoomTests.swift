import Testing
@testable import ElemelekCore

@Suite struct TextZoomTests {
    @Test func stepsMoveByFactor() {
        #expect(TextZoom.zoomIn(1) == 1.15)
        #expect(TextZoom.zoomOut(1) == 0.87)
    }

    @Test func clampsAtBounds() {
        #expect(TextZoom.zoomIn(2) == 2)
        #expect(TextZoom.zoomOut(0.75) == 0.75)
        #expect(TextZoom.clamped(99) == 2)
        #expect(TextZoom.clamped(0) == 0.75)
    }

    @Test func roundTripReturns() {
        #expect(TextZoom.zoomOut(TextZoom.zoomIn(1)) == 1)
    }
}
