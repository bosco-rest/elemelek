import Foundation
import MatrixRustSDK
import ElemelekCore

struct ThreadEntry: Identifiable, Hashable {
    let id: String
    var rootSender: String
    var rootText: String
    var rootLocked = false
    var replies: Int
    var latest: String?
    var date: Date
}

final class ThreadItemsListener: ThreadListEntriesListener, @unchecked Sendable {
    let cb: @Sendable ([ThreadListUpdate]) -> Void
    init(_ f: @escaping @Sendable ([ThreadListUpdate]) -> Void) { cb = f }
    func onUpdate(diff: [ThreadListUpdate]) { cb(diff) }
}

extension AppModel {
    /// Open one thread in the side panel; a message without replies yet becomes a thread when you answer in it.
    func openThread(_ rootEventID: String) async {
        guard let room = currentRoom, let client else { return }
        threadOpening += 1
        let mine = threadOpening
        sidePanel = .thread(rootEventID)
        thread = nil
        do {
            let t = try await room.timelineWithConfiguration(configuration: TimelineConfiguration(
                focus: .thread(rootEventId: rootEventID), filter: .all, internalIdPrefix: "thread-",
                dateDividerMode: .daily, trackReadReceipts: .allEvents, reportUtds: false))
            // Another thread or room was opened meanwhile; don't put this one over it.
            guard threadOpening == mine, sidePanel == .thread(rootEventID), currentRoom === room else { return }
            let m = TimelineModel(timeline: t, client: client, roomID: room.id(), threadRoot: rootEventID)
            thread = m
            await m.start()
        } catch {
            Log.timeline.error("open thread failed: \(error.localizedDescription, privacy: .public)")
            self.error = "\(error)"
        }
    }

    func closeThread() { thread = nil; sidePanel = .none }

    /// All threads of the room, newest first, in the side panel.
    func showThreads() async {
        guard let room = currentRoom else { return }
        sidePanel = .threads
        thread = nil
        await startThreadList(room)
    }

    /// Follow the room's thread list: it feeds the side panel and the reply chips under thread roots on the timeline.
    func startThreadList(_ room: Room, allPages: Bool = false) async {
        if threadService == nil {
            let svc = room.threadListService()
            threadService = svc
            threadHandle = svc.subscribeToItemsUpdates(listener: ThreadItemsListener { [weak self] ups in
                Task { @MainActor in self?.apply(ups) }
            })
            rawThreads = svc.items()
            rebuildThreads()
        }
        guard let svc = threadService else { return }
        // For the timeline's chips every root counts, not only the newest page; stop if the room changes.
        var pages = 0
        repeat {
            // A failed page (no network) ends the run; opening the room or the panel again tries anew.
            guard await Log.sync.attempt("thread paginate", { try await svc.paginate() }) != nil else { break }
            pages += 1
            if case .idle(let end) = svc.paginationState(), end { break }
        } while allPages && pages < 50 && threadService === svc
    }

    func hideSidePanel() { thread = nil; sidePanel = .none }

    func apply(_ ups: [ThreadListUpdate]) {
        for u in ups {
            switch u {
            case .append(let v): rawThreads += v
            case .clear: rawThreads = []
            case .pushFront(let v): rawThreads.insert(v, at: 0)
            case .pushBack(let v): rawThreads.append(v)
            case .popFront: if !rawThreads.isEmpty { rawThreads.removeFirst() }
            case .popBack: if !rawThreads.isEmpty { rawThreads.removeLast() }
            case .insert(let i, let v): rawThreads.insert(v, at: Int(i))
            case .set(let i, let v): rawThreads[Int(i)] = v
            case .remove(let i): rawThreads.remove(at: Int(i))
            case .truncate(let n): rawThreads = Array(rawThreads.prefix(Int(n)))
            case .reset(let v): rawThreads = v
            }
        }
        rebuildThreads()
    }

    func rebuildThreads() {
        threads = rawThreads.map { it in
            let latest = it.latestEvent.map {
                TimelineModel.senderName($0.sender, $0.senderProfile) + ": " + TimelineModel.summary(of: $0.content)
            }
            return ThreadEntry(
                id: it.rootEvent.eventId,
                rootSender: TimelineModel.senderName(it.rootEvent.sender, it.rootEvent.senderProfile),
                rootText: TimelineModel.summary(of: it.rootEvent.content),
                rootLocked: TimelineModel.isLocked(it.rootEvent.content),
                replies: Int(it.numReplies), latest: latest,
                date: Date(timeIntervalSince1970: Double((it.latestEvent ?? it.rootEvent).timestamp) / 1000))
        }.sorted { $0.date > $1.date }
        timeline?.threadInfo = Dictionary(threads.map { ($0.id, ThreadInfo(replies: $0.replies, latest: $0.latest)) },
                                          uniquingKeysWith: { a, _ in a })
    }
}
