import Testing
@testable import ElemelekCore

@Suite struct PageRetryTests {
    @Test func noFailureMeansTheShortSettleWait() {
        #expect(PageRetry.delay(afterFailures: 0) == 300)
        #expect(PageRetry.delay(afterFailures: -1) == 300)
    }

    @Test func failuresBackOffDoubling() {
        #expect(PageRetry.delay(afterFailures: 1) == 2_000)
        #expect(PageRetry.delay(afterFailures: 2) == 4_000)
        #expect(PageRetry.delay(afterFailures: 3) == 8_000)
        #expect(PageRetry.delay(afterFailures: 4) == 16_000)
    }

    @Test func stopsRetryingOnItsOwnAfterTheLimit() {
        #expect(PageRetry.delay(afterFailures: PageRetry.maxAutomatic) == nil)
        #expect(PageRetry.delay(afterFailures: 100) == nil)
    }
}
