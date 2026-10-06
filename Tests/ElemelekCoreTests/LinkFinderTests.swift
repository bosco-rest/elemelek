import Foundation
import Testing
@testable import ElemelekCore

@Suite struct LinkFinderTests {
    @Test func findsLinksInOrder() {
        let urls = LinkFinder.all(in: "see https://a.example/x and http://b.example")
        #expect(urls.map(\.host) == ["a.example", "b.example"])
    }

    @Test func repeatedLinkCountsOnce() {
        #expect(LinkFinder.all(in: "https://a.example https://a.example").count == 1)
    }

    @Test func limitsTheCount() {
        let text = (1...6).map { "https://site\($0).example" }.joined(separator: " ")
        #expect(LinkFinder.all(in: text, limit: 2).count == 2)
        #expect(LinkFinder.all(in: text).count == 3)
    }

    @Test func ignoresNonWebLinks() {
        #expect(LinkFinder.all(in: "mail me: mailto:a@b.example").isEmpty)
    }

    @Test func plainTextHasNone() {
        #expect(LinkFinder.all(in: "no links here").isEmpty)
    }
}
