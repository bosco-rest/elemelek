import Foundation
import Testing
@testable import ElemelekCore

@Suite struct SyntaxTests {
    private func kinds(_ text: String, _ lang: Syntax.Language) -> [Syntax.Kind] {
        Syntax.tokens(text, lang).map(\.kind)
    }

    @Test func languageByFileName() {
        #expect(Syntax.language(forPath: "/a/b/main.swift") == .swift)
        #expect(Syntax.language(forPath: "data.JSON") == .json)
        #expect(Syntax.language(forPath: "Makefile") == .shell)
        #expect(Syntax.language(forPath: "photo.png") == nil)
    }

    @Test func guessesJSONOnly() {
        #expect(Syntax.guess("  {\"a\": 1}  ") == .json)
        #expect(Syntax.guess("[1, 2]") == .json)
        #expect(Syntax.guess("hello") == .plain)
    }

    @Test func plainHasNoTokens() {
        #expect(Syntax.tokens("anything at all", .plain).isEmpty)
    }

    @Test func jsonTokens() {
        let k = kinds(#"{"a": 1, "b": true}"#, .json)
        #expect(k.contains(.key))
        #expect(k.contains(.number))
        #expect(k.contains(.literal))
    }

    @Test func tokensStayInsideTheText() {
        let text = "let s = \"héllo 🌍\" // done\nreturn 42"
        let length = text.utf16.count
        for t in Syntax.tokens(text, .swift) {
            #expect(t.start >= 0 && t.length > 0 && t.start + t.length <= length)
        }
    }

    @Test func swiftKeywordsStringsComments() {
        let k = kinds("let a = \"x\" // c", .swift)
        #expect(k.contains(.keyword))
        #expect(k.contains(.string))
        #expect(k.contains(.comment))
    }

    @Test func prettyJSONIndentsLongMinifiedJSON() {
        let minified = "{" + (1...12).map { "\"key\($0)\":[1,2]" }.joined(separator: ",") + "}"
        let out = Syntax.prettyJSON(minified)
        #expect(out.contains("\n  \"key1\": [\n    1,\n    2\n  ],\n  \"key2\""))
        #expect(out.hasSuffix("}\n"))
    }

    @Test func prettyJSONLeavesShortOrInvalidTextAlone() {
        #expect(Syntax.prettyJSON(#"{"a":1}"#) == #"{"a":1}"#)
        let broken = String(repeating: "{x", count: 80)
        #expect(Syntax.prettyJSON(broken) == broken)
    }
}
