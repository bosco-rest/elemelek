import Testing
@testable import ElemelekCore

@Suite struct ListDiffTests {
    @Test func positionalDiffsApplyInOrder() {
        var a = [1, 2, 3]
        let out = a.apply([.pushFront(0), .insert(2, 9), .set(0, 10), .remove(1), .pushBack(4), .popFront, .append([5, 6])])
        #expect(a == [9, 2, 3, 4, 5, 6])
        #expect(out == ListDiffOutcome())
    }

    @Test func truncateAndPops() {
        var a = [1, 2, 3, 4]
        a.apply([.truncate(3), .popBack, .popFront])
        #expect(a == [2])
        var empty: [Int] = []
        empty.apply([.popBack, .popFront, .truncate(5)])
        #expect(empty.isEmpty)
    }

    @Test func clearAndResetAreReported() {
        var a = [1, 2]
        let cleared = a.apply([.clear])
        #expect(cleared.cleared && !cleared.reset)
        #expect(a.isEmpty)
        let reset = a.apply([.reset([7, 8])])
        #expect(reset.reset && !reset.cleared)
        #expect(a == [7, 8])
        let pushed = a.apply([.pushBack(9)])
        #expect(pushed == ListDiffOutcome())
    }

    @Test func diffsPastTheEndAreCountedNotCrashed() {
        var a = [1]
        let out = a.apply([.set(3, 0), .remove(1), .insert(5, 0), .insert(1, 2)])
        #expect(a == [1, 2])
        #expect(out.outOfRange == 3)
    }
}
