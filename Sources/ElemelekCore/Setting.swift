import Foundation

/// The user's switches, with their keys and defaults in one place. The settings window binds to the same keys
/// through `@AppStorage(Setting.banners.key)`, so a typo is a compile error rather than a setting that silently
/// never changes.
public enum Setting: String, CaseIterable, Sendable {
    case banners, notificationSound, typingNotices, readReceipts, alwaysHD, linkPreviews, showReadReceipts

    public var key: String { rawValue }

    /// What the switch is until the user touches it.
    public var defaultValue: Bool {
        switch self {
        case .alwaysHD: false
        default: true
        }
    }

    public func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}

/// Rooms whose history is already in the search index, so a restart does not index them again.
public struct IndexedRooms {
    private static let key = "indexedRooms"
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var ids: Set<String> { Set(defaults.stringArray(forKey: Self.key) ?? []) }

    public func insert(_ id: String) {
        defaults.set(Array(ids.union([id])), forKey: Self.key)
    }
}
