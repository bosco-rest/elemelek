import AppKit
import MatrixRustSDK

extension AppModel {
    // MARK: Invites, join, create, leave

    func acceptInvite(_ id: String) async {
        guard let room = roomObjects.first(where: { $0.id() == id }) else { return }
        do { try await room.join(); await select(id) } catch { self.error = "\(error)" }
    }

    func declineInvite(_ id: String) async {
        guard let room = roomObjects.first(where: { $0.id() == id }) else { return }
        do { try await room.leave() } catch { self.error = "\(error)" }
    }

    func roomObject(_ id: String) -> Room? { roomObjects.first { $0.id() == id } }

    func leaveRoom(_ id: String) async {
        guard let room = roomObjects.first(where: { $0.id() == id }) else { return }
        do {
            try await room.leave()
            if selectedRoomID == id { await select(nil) }
        } catch { self.error = "\(error)" }
    }

    /// Opens a room once the room list has caught up with it (the sync can lag behind the request).
    func openWhenListed(_ id: String) async {
        for _ in 0..<40 {
            if roomObjects.contains(where: { $0.id() == id }) { await select(id); return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Returns an error message, or nil on success.
    func joinRoom(_ target: String) async -> String? {
        guard let client else { return nil }
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        var via: [String] = []
        if let colon = t.firstIndex(of: ":") { via = [String(t[t.index(after: colon)...])] }
        do {
            let room = try await client.joinRoomByIdOrAlias(roomIdOrAlias: t, serverNames: via)
            await openWhenListed(room.id())
            return nil
        } catch { return "\(error)" }
    }

    func createRoom(name: String, topic: String, isPublic: Bool) async -> String? {
        guard let client else { return nil }
        let params = CreateRoomParameters(name: name, topic: topic.isEmpty ? nil : topic, isEncrypted: !isPublic,
                                          visibility: isPublic ? .public : .private,
                                          preset: isPublic ? .publicChat : .privateChat)
        do {
            let id = try await client.createRoom(request: params)
            await openWhenListed(id)
            return nil
        } catch { return "\(error)" }
    }

    func searchUsers(_ term: String) async -> [UserProfile] {
        guard let client, !term.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return (try? await client.searchUsers(searchTerm: term, limit: 12))?.results ?? []
    }

    /// Opens the existing direct chat with a user, or creates an encrypted one.
    func startDirect(_ userId: String) async -> String? {
        guard let client else { return nil }
        do {
            if let room = try client.getDmRoom(userId: userId) { await select(room.id()); return nil }
            let params = CreateRoomParameters(name: nil, isEncrypted: true, isDirect: true, visibility: .private,
                                              preset: .trustedPrivateChat, invite: [userId])
            let id = try await client.createRoom(request: params)
            await openWhenListed(id)
            return nil
        } catch { return "\(error)" }
    }

    func markCurrentRead() { timeline?.markRead(force: true) }
}
