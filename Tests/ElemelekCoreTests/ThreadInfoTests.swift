import Testing
@testable import ElemelekCore

@Suite struct ThreadInfoTests {
    @Test func noInfoKeepsEvent() {
        #expect(ThreadInfo.merge(replies: 2, latest: "a", with: nil) == (2, "a"))
    }
    @Test func listKnowsMore() {
        #expect(ThreadInfo.merge(replies: 0, latest: nil, with: .init(replies: 3, latest: "b")) == (3, "b"))
        #expect(ThreadInfo.merge(replies: 1, latest: "a", with: .init(replies: 3, latest: nil)) == (3, "a"))
    }
    @Test func equalCountFillsMissingLatest() {
        #expect(ThreadInfo.merge(replies: 2, latest: nil, with: .init(replies: 2, latest: "b")) == (2, "b"))
        #expect(ThreadInfo.merge(replies: 2, latest: "a", with: .init(replies: 2, latest: "b")) == (2, "a"))
    }
    @Test func eventKnowsMore() {
        #expect(ThreadInfo.merge(replies: 5, latest: "a", with: .init(replies: 3, latest: "b")) == (5, "a"))
    }
}
