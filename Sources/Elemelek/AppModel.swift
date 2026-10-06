import AppKit
import Foundation
import UserNotifications
import Observation
import ElemelekCore
import MatrixRustSDK

struct RoomEntry: Identifiable, Hashable {
    let id: String
    var name: String
    var avatarURL: String?
    var isDirect: Bool
    var isSpace = false
    var notifications: UInt64 = 0
    var highlights: UInt64 = 0
    var markedUnread = false
    /// Unread messages and mentions counted locally, for rooms whose push rules stay quiet.
    var unreadMessages: UInt64 = 0
    var mentions: UInt64 = 0
    var invited = false
    var inviter: String?
    var hasUnread: Bool { notifications > 0 || highlights > 0 || markedUnread || unreadMessages > 0 }
    var mentioned: Bool { highlights > 0 || mentions > 0 }
}

final class RoomInfoSink: RoomInfoListener, @unchecked Sendable {
    let onInfo: @Sendable (RoomInfo) -> Void
    init(_ f: @escaping @Sendable (RoomInfo) -> Void) { onInfo = f }
    func call(roomInfo: RoomInfo) { onInfo(roomInfo) }
}

final class RoomsListener: RoomListEntriesListener, @unchecked Sendable {
    let onUpdate: @Sendable ([RoomListEntriesUpdate]) -> Void
    init(_ f: @escaping @Sendable ([RoomListEntriesUpdate]) -> Void) { onUpdate = f }
    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) { onUpdate(roomEntriesUpdate) }
}

@MainActor @Observable
final class AppModel {
    enum State { case starting, loggedOut, syncing }
    var state: State = .starting
    var error: String?
    var rooms: [RoomEntry] = []
    /// Your own picture on the homeserver.
    var myAvatar: String?
    var selectedRoomID: String?
    var timeline: TimelineModel?
    var thread: TimelineModel?
    var sidePanel: SidePanel = .none
    var threads: [ThreadEntry] = []
    var lightbox: Lightbox?
    var indexDone = 0
    var indexTotal = 0
    var currentRoom: Room?
    var rawThreads: [ThreadListItem] = []
    var threadService: ThreadListService?
    var threadHandle: TaskHandle?
    var threadPageHandle: TaskHandle?
    var indexTask: Task<Void, Never>?
    var indexStarted = false

    var verified = true
    var verification: VerificationFlow = .idle
    var verifyController: SessionVerificationController?
    var verifyDelegate: VerifyDelegate?
    var recoveryMessage: String?
    var searchHits: [SearchHit] = []
    var rawHits: [SearchServiceResult] = []
    var searchService: SearchService?
    var searchHandle: TaskHandle?

    var client: Client?
    var syncService: SyncService?
    var roomList: RoomList?
    var roomObjects: [Room] = []
    /// Display names of the people typing in the open room (not you).
    var typingNames: [String] = []
    var typingHandle: TaskHandle?
    var typingSent: Date?
    var notifiedCounts: [String: UInt64] = [:]
    var notifDelegate: NotificationDelegate?
    var roomInfos: [String: RoomInfo] = [:]
    var infoHandles: [String: TaskHandle] = [:]
    var handles: [Any] = []

    var baseDir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Elemelek", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    var sessions: SessionStore { SessionStore(legacyFile: baseDir.appendingPathComponent("session.json")) }

    /// The stores belong to one device of one account; a new login makes a new device, so they start empty.
    func wipeStores() {
        for p in ["data", "cache", "search"] { try? FileManager.default.removeItem(at: baseDir.appendingPathComponent(p)) }
    }

    func makeBuilder() -> ClientBuilder {
        ClientBuilder()
            .sessionPaths(dataPath: baseDir.appendingPathComponent("data").path,
                          cachePath: baseDir.appendingPathComponent("cache").path)
            .withSearchIndexStore(path: baseDir.appendingPathComponent("search").path, password: nil)
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .threadsEnabled(enabled: true, threadSubscriptions: false)
            // Fetch a missing room key from the backup when a message fails to decrypt; the timeline then redraws it.
            .backupDownloadStrategy(backupDownloadStrategy: .afterDecryptionFailure)
            .autoEnableBackups(autoEnableBackups: true)
    }

    func start() async {
        guard let s = sessions.load() else { state = .loggedOut; return }
        do {
            let c = try await makeBuilder().homeserverUrl(url: s.homeserverUrl).build()
            try await c.restoreSession(session: Session(accessToken: s.accessToken, refreshToken: s.refreshToken,
                userId: s.userId, deviceId: s.deviceId, homeserverUrl: s.homeserverUrl,
                oauthData: nil, slidingSyncVersion: .native))
            await begin(c)
        } catch {
            self.error = "\(error)"; state = .loggedOut
        }
    }

    func login(server: String, user: String, password: String) async {
        error = nil
        wipeStores()
        do {
            let c = try await makeBuilder().serverNameOrHomeserverUrl(serverNameOrUrl: server).build()
            try await c.login(username: user, password: password, initialDeviceName: "Elemelek", deviceId: nil)
            let s = try c.session()
            let stored = StoredSession(accessToken: s.accessToken, refreshToken: s.refreshToken,
                userId: s.userId, deviceId: s.deviceId, homeserverUrl: s.homeserverUrl)
            if !sessions.save(stored) { Log.session.error("could not save the session to the Keychain") }
            await begin(c)
        } catch {
            self.error = "\(error)"
        }
    }

    func begin(_ c: Client) async {
        client = c
        AvatarStore.shared.client = c
        Task { myAvatar = await Log.session.attempt("load own avatar") { try await c.avatarUrl() } ?? nil }
        do {
            let sync = try await c.syncService().finish()
            syncService = sync
            let list = try await sync.roomListService().allRooms()
            roomList = list
            let listener = RoomsListener { [weak self] updates in
                Task { @MainActor in self?.apply(updates) }
            }
            let res = list.entriesWithDynamicAdapters(pageSize: 200, listener: listener)
            _ = res.controller().setFilter(kind: .all(filters: [.nonLeft]))
            handles.append(res)
            await sync.start()
            verified = c.encryption().verificationState() == .verified
            handles.append(c.encryption().verificationStateListener(listener: VerifyStateListener { [weak self] status in
                Task { @MainActor in self?.verified = status == .verified }
            }))
            state = .syncing
            setUpNotifications()
        } catch {
            self.error = "\(error)"; state = .loggedOut
        }
    }

    func recover(_ key: String) async {
        guard let client else { return }
        recoveryMessage = nil
        do {
            try await client.encryption().recover(recoveryKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
            verified = client.encryption().verificationState() == .verified
            recoveryMessage = verified ? nil : String(localized: "Recovery key accepted; waiting for sync to finish.")
        } catch { recoveryMessage = "\(error)" }
    }

    func logout() async {
        await Log.session.attempt("logout") { try await client?.logout() }
        sessions.clear()
        await syncService?.stop()
        indexTask?.cancel(); indexStarted = false
        infoHandles = [:]; roomInfos = [:]; NSApp.dockTile.badgeLabel = nil
        client = nil; syncService = nil; roomObjects = []; rooms = []; timeline = nil; thread = nil; selectedRoomID = nil
        sidePanel = .none; threads = []; lightbox = nil
        wipeStores()
        state = .loggedOut
    }


    func apply(_ updates: [RoomListEntriesUpdate]) {
        for u in updates {
            switch u {
            case .append(let v): roomObjects += v
            case .clear: roomObjects = []
            case .pushFront(let v): roomObjects.insert(v, at: 0)
            case .pushBack(let v): roomObjects.append(v)
            case .popFront: if !roomObjects.isEmpty { roomObjects.removeFirst() }
            case .popBack: if !roomObjects.isEmpty { roomObjects.removeLast() }
            case .insert(let i, let v): roomObjects.insert(v, at: Int(i))
            case .set(let i, let v): roomObjects[Int(i)] = v
            case .remove(let i): roomObjects.remove(at: Int(i))
            case .truncate(let n): roomObjects = Array(roomObjects.prefix(Int(n)))
            case .reset(let v): roomObjects = v
            }
        }
        for r in roomObjects where infoHandles[r.id()] == nil {
            let id = r.id()
            infoHandles[id] = r.subscribeToRoomInfoUpdates(listener: RoomInfoSink { [weak self] info in
                Task { @MainActor in self?.roomInfos[id] = info; self?.rebuildRooms() }
            })
            Task { if let info = await Log.sync.attempt("load room info", { try await r.roomInfo() }) { roomInfos[id] = info; rebuildRooms() } }
        }
        rebuildRooms()
        if !indexStarted, !roomObjects.isEmpty {
            indexStarted = true
            startIndexing()
        }
    }

    func rebuildRooms() {
        rooms = roomObjects.map { r in
            let id = r.id()
            let i = roomInfos[id]
            return RoomEntry(id: id, name: r.displayName() ?? i?.displayName ?? id, avatarURL: i?.avatarUrl, isDirect: i?.isDirect ?? false,
                             isSpace: i?.isSpace ?? false, notifications: i?.notificationCount ?? 0,
                             highlights: i?.highlightCount ?? 0, markedUnread: i?.isMarkedUnread ?? false,
                             unreadMessages: i?.numUnreadMessages ?? 0, mentions: i?.numUnreadMentions ?? 0,
                             invited: i?.membership == .invited,
                             inviter: i?.inviter.map { $0.displayName ?? $0.userId })
        }
        notifyAboutNew()
        let total = rooms.filter { !$0.isSpace && !$0.invited }.reduce(0) { $0 + Int($1.notifications) }
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
    }



    // MARK: Rooms and threads

    func select(_ id: String?) async {
        selectedRoomID = id
        timeline = nil; thread = nil; sidePanel = .none; typingHandle = nil; typingNames = []
        threads = []; rawThreads = []; threadService = nil; threadHandle = nil; threadPageHandle = nil
        // The old room's rows and pictures are gone now; hand the freed pages back instead of keeping them.
        malloc_zone_pressure_relief(nil, 0)
        guard let id, let room = roomObjects.first(where: { $0.id() == id }), let client else { return }
        currentRoom = room
        typingSent = nil
        watchTyping(room)
        do {
            let t = try await room.timelineWithConfiguration(configuration: TimelineConfiguration(
                focus: .live(hideThreadedEvents: true), filter: .all, internalIdPrefix: nil,
                dateDividerMode: .daily, trackReadReceipts: .allEvents, reportUtds: false))
            let m = TimelineModel(timeline: t, client: client, roomID: id)
            timeline = m
            await m.start()
            m.markRead(force: true)
        } catch { self.error = "\(error)" }
    }


}

enum SidePanel: Equatable {
    case none, threads, thread(String)
}

struct Lightbox {
    let row: TimelineRow
    let model: TimelineModel
}
