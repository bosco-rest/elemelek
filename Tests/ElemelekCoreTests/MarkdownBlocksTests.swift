import Testing
@testable import ElemelekCore

@Suite struct MarkdownBlocksTests {
    @Test func headingsAndParagraphs() {
        let blocks = MarkdownBlocks.parse("# Title\n\nSome text")
        #expect(blocks == [.heading(level: 1, text: "Title"), .paragraph("Some text")])
    }

    @Test func fencedCodeKeepsItsLines() {
        let blocks = MarkdownBlocks.parse("```\nlet a = 1\n\nlet b = 2\n```")
        #expect(blocks == [.code("let a = 1\n\nlet b = 2")])
    }

    @Test func unterminatedFenceStillYieldsCode() {
        #expect(MarkdownBlocks.parse("```\nlet a = 1") == [.code("let a = 1")])
    }

    @Test func bulletsAndCheckboxes() {
        let blocks = MarkdownBlocks.parse("- one\n- [x] done\n- [ ] todo")
        guard case .list(let items) = blocks.first else { Issue.record("not a list"); return }
        #expect(items.map(\.mark) == [.bullet, .check(true), .check(false)])
        #expect(items.map(\.text) == ["one", "done", "todo"])
    }

    @Test func numbersKeepCountingAcrossASubList() {
        let blocks = MarkdownBlocks.parse("1. a\n   - x\n2. b")
        guard case .list(let items) = blocks.first else { Issue.record("not a list"); return }
        #expect(items.map(\.depth) == [0, 1, 0])
        #expect(items[2].mark == .number(2))
    }

    @Test func listMarkers() {
        #expect(MarkdownBlocks.listMarker("- a")?.text == "a")
        #expect(MarkdownBlocks.listMarker("3) c")?.mark == .number(3))
        #expect(MarkdownBlocks.listMarker("-")?.mark == .bullet)
        #expect(MarkdownBlocks.listMarker("-a") == nil)
        #expect(MarkdownBlocks.listMarker("1.a") == nil)
        #expect(MarkdownBlocks.listMarker("plain") == nil)
    }

    @Test func indentCountsTabsAsFour() {
        #expect(MarkdownBlocks.indent("  x") == 2)
        #expect(MarkdownBlocks.indent("\tx") == 4)
        #expect(MarkdownBlocks.indent("x") == 0)
    }

    @Test func quotes() {
        #expect(MarkdownBlocks.parse("> wise\n> words") == [.quote("wise\nwords")])
    }

    @Test func tablesWithAlignment() {
        let blocks = MarkdownBlocks.parse("| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 | 3 |")
        #expect(blocks == [.table(header: ["a", "b", "c"], align: [.leading, .center, .trailing], rows: [["1", "2", "3"]])])
    }

    @Test func emptyInputHasNoBlocks() {
        #expect(MarkdownBlocks.parse("").isEmpty)
    }
}
