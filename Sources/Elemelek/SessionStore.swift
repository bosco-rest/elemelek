import Foundation
import Security

struct StoredSession: Codable {
    var accessToken: String
    var refreshToken: String?
    var userId: String
    var deviceId: String
    var homeserverUrl: String
}

/// Keeps the login in the Keychain, so the tokens are not left in a file anyone who can read the disk can read.
/// A `session.json` from an earlier version is moved into the Keychain on first load and deleted.
struct SessionStore {
    private let service = "rest.bosco.elemelek"
    private let account = "session"
    /// Where an earlier version kept the session; only read to migrate it.
    let legacyFile: URL

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> StoredSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
           let session = try? JSONDecoder().decode(StoredSession.self, from: data) {
            return session
        }
        guard let data = try? Data(contentsOf: legacyFile),
              let session = try? JSONDecoder().decode(StoredSession.self, from: data) else { return nil }
        if save(session) { try? FileManager.default.removeItem(at: legacyFile) }
        return session
    }

    @discardableResult
    func save(_ session: StoredSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
        try? FileManager.default.removeItem(at: legacyFile)
    }
}
