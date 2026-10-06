import Foundation
import Testing
@testable import ElemelekCore

@Suite struct ReadReceiptTests {
    @Test func readReceiptProperties() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let receipt = ReadReceipt(userID: "@alice:matrix.org", displayName: "Alice", avatarURL: "mxc://example.com/avatar", date: date)
        #expect(receipt.id == "@alice:matrix.org")
        #expect(receipt.userID == "@alice:matrix.org")
        #expect(receipt.displayName == "Alice")
        #expect(receipt.avatarURL == "mxc://example.com/avatar")
        #expect(receipt.date == date)
    }

    @Test func summaryFormatting() {
        let r1 = ReadReceipt(userID: "@alice:x", displayName: "Alice")
        let r2 = ReadReceipt(userID: "@bob:x", displayName: "Bob")
        let r3 = ReadReceipt(userID: "@carol:x", displayName: "Carol")
        let r4 = ReadReceipt(userID: "@dave:x", displayName: "Dave")
        let r5 = ReadReceipt(userID: "@eve:x", displayName: "Eve")

        #expect(ReadReceiptFormatter.summary(for: []) == "")
        #expect(ReadReceiptFormatter.summary(for: [r1]) == "Read by Alice")
        #expect(ReadReceiptFormatter.summary(for: [r1, r2]) == "Read by Alice, Bob")
        #expect(ReadReceiptFormatter.summary(for: [r1, r2, r3]) == "Read by Alice, Bob, Carol")
        #expect(ReadReceiptFormatter.summary(for: [r1, r2, r3, r4]) == "Read by Alice, Bob +2")
        #expect(ReadReceiptFormatter.summary(for: [r1, r2, r3, r4, r5]) == "Read by Alice, Bob +3")
    }

    @Test func labelFormattingWithStyles() {
        let r1 = ReadReceipt(userID: "@alice:x", displayName: "Alice")
        let r2 = ReadReceipt(userID: "@bob:x", displayName: "Bob")

        #expect(ReadReceiptFormatter.label(for: [r1, r2], style: .avatarsOnly) == "")
        #expect(ReadReceiptFormatter.label(for: [r1, r2], style: .namesOnly) == "Read by Alice, Bob")
        #expect(ReadReceiptFormatter.label(for: [r1, r2], style: .avatarsAndNames) == "Read by Alice, Bob")
    }

    @Test func tooltipFormatting() {
        let r1 = ReadReceipt(userID: "@alice:x", displayName: "Alice")
        #expect(ReadReceiptFormatter.tooltip(for: [r1]) == "Read by Alice")

        let date = Date(timeIntervalSince1970: 1700000000)
        let r2 = ReadReceipt(userID: "@bob:x", displayName: "Bob", date: date)
        let tip = ReadReceiptFormatter.tooltip(for: [r2])
        #expect(tip.hasPrefix("Read by Bob ("))
        #expect(tip.hasSuffix(")"))
    }

    @Test func styleEnumKeysAndDefaults() {
        #expect(ReadReceiptStyle.key == "readReceiptStyle")
        #expect(ReadReceiptStyle.defaultValue == .avatarsAndNames)
        #expect(ReadReceiptStyle.allCases.count == 3)
    }

    @Test func showReadReceiptsSetting() {
        let d = UserDefaults(suiteName: "elemelek.tests.\(UUID().uuidString)")!
        #expect(Setting.showReadReceipts.isOn(d))
        d.set(false, forKey: Setting.showReadReceipts.key)
        #expect(!Setting.showReadReceipts.isOn(d))
    }
}
