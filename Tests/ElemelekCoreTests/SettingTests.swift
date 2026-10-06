import Foundation
import Testing
@testable import ElemelekCore

@Suite struct SettingTests {
    private func defaults() -> UserDefaults {
        let name = "elemelek.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func defaultsApplyUntilTouched() {
        let d = defaults()
        #expect(Setting.banners.isOn(d))
        #expect(!Setting.alwaysHD.isOn(d))
    }

    @Test func storedValueWins() {
        let d = defaults()
        d.set(false, forKey: Setting.banners.key)
        d.set(true, forKey: Setting.alwaysHD.key)
        #expect(!Setting.banners.isOn(d))
        #expect(Setting.alwaysHD.isOn(d))
    }

    @Test func keysAreUnique() {
        #expect(Set(Setting.allCases.map(\.key)).count == Setting.allCases.count)
    }

    @Test func indexedRoomsAccumulate() {
        let d = defaults()
        let rooms = IndexedRooms(d)
        rooms.insert("!a:x"); rooms.insert("!b:x"); rooms.insert("!a:x")
        #expect(rooms.ids == ["!a:x", "!b:x"])
    }
}
