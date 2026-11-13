import Foundation
import Testing
@testable import ElemelekCore

private struct Msg: GroupedMessage {
    var senderID: String
    var senderName: String
    var date: Date?
}

private let base = Date(timeIntervalSince1970: 1_780_000_000)

private func msg(_ id: String = "@a:x", _ name: String = "Ann", _ offset: TimeInterval = 0) -> Msg {
    Msg(senderID: id, senderName: name, date: base.addingTimeInterval(offset))
}

@Suite struct MessageGroupingTests {
    @Test func firstMessageShowsHeader() {
        #expect(MessageGrouping.showsHeader(current: msg(), previous: nil))
    }

    @Test func quickSuccessionGroups() {
        #expect(!MessageGrouping.showsHeader(current: msg("@a:x", "Ann", 240), previous: msg()))
    }

    @Test func anotherSenderBreaksGroup() {
        #expect(MessageGrouping.showsHeader(current: msg("@b:x", "Bob", 10), previous: msg()))
    }

    @Test func sameNameDifferentPersonBreaksGroup() {
        #expect(MessageGrouping.showsHeader(current: msg("@b:x", "Ann", 10), previous: msg()))
    }

    @Test func renameBreaksGroup() {
        #expect(MessageGrouping.showsHeader(current: msg("@a:x", "Annie", 10), previous: msg()))
    }

    @Test func gapBreaksGroup() {
        #expect(MessageGrouping.showsHeader(current: msg("@a:x", "Ann", 301), previous: msg()))
        #expect(!MessageGrouping.showsHeader(current: msg("@a:x", "Ann", 300), previous: msg()))
    }

    @Test func midnightBreaksGroup() {
        // either side of local midnight: 2 minutes apart, but a different day.
        let midnight = Calendar.current.startOfDay(for: Date())
        let prev = Msg(senderID: "@a:x", senderName: "Ann", date: midnight.addingTimeInterval(-60))
        let cur = Msg(senderID: "@a:x", senderName: "Ann", date: midnight.addingTimeInterval(60))
        #expect(MessageGrouping.showsHeader(current: cur, previous: prev))
    }

    @Test func missingOrScrambledDatesShowHeader() {
        let nodate = Msg(senderID: "@a:x", senderName: "Ann", date: nil)
        #expect(MessageGrouping.showsHeader(current: nodate, previous: msg()))
        #expect(MessageGrouping.showsHeader(current: msg(), previous: nodate))
        #expect(MessageGrouping.showsHeader(current: msg("@a:x", "Ann", -10), previous: msg()))
    }
}
