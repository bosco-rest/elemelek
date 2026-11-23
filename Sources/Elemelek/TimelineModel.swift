import AppKit
import Foundation
import Observation
import MatrixRustSDK
import UniformTypeIdentifiers
import ElemelekCore

struct ReactionChip: Hashable, Identifiable {
    var id: String { key }
    var key: String
    var count: Int
    var mine: Bool
    var names: [String]
}

struct ReplyPreview: Hashable {
    var sender: String
    var text: String
    var eventID: String
}

struct MediaInfo: Hashable {
    enum Kind { case image, video, audio, file }
    var kind: Kind
    var name: String
    var size: UInt64?
    var duration: TimeInterval?
    var isVoice = false
    /// Picture size in pixels, when the sender said; lets the timeline reserve the space before it loads.
    var pixels: CGSize?
}

struct TimelineRow: Identifiable, Hashable {
    let id: String
    var sender: String
    var senderID: String = ""
    var senderAvatar: String?
    var locked = false
    var text: String
    var isOwn: Bool
    var date: Date?
    var eventID: String?
    var reactions: [ReactionChip] = []
    var isEditable = false
    var isEdited = false
    var reply: ReplyPreview?
    var media: MediaInfo?
    /// Set when this event is a reply inside a thread.
    var threadRoot: String?
    /// For a thread root: how many replies it has, and the newest one.
    var threadReplies = 0
    var threadLatest: String?
    var readReceipts: [ReadReceipt] = []

    var hasImage: Bool { media?.kind == .image }
    var imageName: String? { media?.name }
}

extension TimelineRow: ComposerMessage {}

extension TimelineRow: GroupedMessage {
    var senderName: String { sender }
}

final class TLListener: TimelineListener, @unchecked Sendable {
    let cb: @Sendable ([TimelineDiff]) -> Void
    init(_ f: @escaping @Sendable ([TimelineDiff]) -> Void) { cb = f }
    func onUpdate(diff: [TimelineDiff]) { cb(diff) }
}

/// One timeline: a room's main one, or a single thread. Owns its rows and everything you do to them.
@MainActor @Observable
final class TimelineModel: Identifiable {
    /// Unique for the life of the app, unlike an object address that a later model may reuse.
    let id = UUID()
    let timeline: Timeline
    let threadRoot: String?
    let roomID: String
    /// Thread counts by root event ID, from the thread list; used where the event itself carries no summary.
    var threadInfo: [String: ThreadInfo] = [:] { didSet { if threadInfo != oldValue { rebuildRows() } } }
    private let client: Client
    private let ownID: String

    var rows: [TimelineRow] = []
    var replyingTo: TimelineRow?
    var editing: TimelineRow?
    var error: String?
    /// Whether the room's start is loaded; reset when the SDK drops the timeline (see `HistoryPaging`).
    private(set) var paging = HistoryPaging()
    var hitStart: Bool { paging.hitStart }
    var loadingMore = false
    /// Why the last page of older messages failed, if it did; cleared by the next page that loads.
    var pageError: String?
    /// Pages failed in a row, so retries back off instead of hammering a server that is down.
    var pageFailures = 0
    /// Bumped after every finished page, so a spinner that is still on screen asks for the next one.
    var pageTick = 0
    var attachments: [Attachment] = []
    var sending = false

    private var itemIDs: [String: EventOrTransactionId] = [:]
    private var imageSources: [String: MediaSource] = [:]
    private var mediaSources: [String: MediaSource] = [:]
    private var thumbSources: [String: MediaSource] = [:]
    /// Decoded thumbnails, bounded by bytes so a long scroll does not keep every picture alive.
    private let imageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 48 << 20
        return c
    }()
    @ObservationIgnored private nonisolated(unsafe) var handle: TaskHandle?
    /// Diffs from the SDK, in the order it sent them; finished when the model goes, which ends its reader.
    /// Each batch carries the number of the listener that sent it, so a replaced listener's last batches are dropped.
    private let diffs: AsyncStream<(listener: Int, diffs: [TimelineDiff])>
    private let diffSink: AsyncStream<(listener: Int, diffs: [TimelineDiff])>.Continuation
    private var listener = 0
    /// Times the listener was replaced after our rows stopped matching the SDK's; bounded so it cannot loop.
    private var relistens = 0
    private var memberProfiles: [String: (name: String, avatar: String?)] = [:]
    private var pendingProfileFetches: Set<String> = []

    init(timeline: Timeline, client: Client, roomID: String, threadRoot: String? = nil) {
        self.timeline = timeline
        self.client = client
        self.roomID = roomID
        self.threadRoot = threadRoot
        self.ownID = (try? client.userId()) ?? ""
        (diffs, diffSink) = AsyncStream.makeStream(of: (listener: Int, diffs: [TimelineDiff]).self)
    }

    deinit {
        handle?.cancel()
        diffSink.finish()
    }

    func start() async {
        // Diffs are positional (insert at 3, remove 7), so they must be applied in the order they were sent.
        // A Task per callback does not promise that; one stream read by one task does.
        let diffs = diffs
        await listen()
        Task { [weak self] in
            for await batch in diffs {
                guard let self else { return }
                guard batch.listener == self.listener else { continue }
                self.apply(batch.diffs)
            }
        }
        await loadMore()
        Task { [weak self] in await self?.loadRoomMembers() }
    }

    /// Adds a listener; its first batch is the whole timeline as a `reset`.
    private func listen() async {
        listener += 1
        let n = listener, sink = diffSink
        handle?.cancel()
        paging.relisten()
        handle = await timeline.addListener(listener: TLListener { sink.yield((n, $0)) })
    }

    private var lastRead: String?

    /// Sends a read receipt for the newest event while the window is in front (not for thread timelines).
    func markRead(force: Bool = false) {
        guard threadRoot == nil, NSApp.isActive, let last = rows.last?.eventID ?? rows.last?.id else { return }
        if !force, last == lastRead { return }
        lastRead = last
        let t = timeline
        let type: ReceiptType = Setting.readReceipts.isOn() ? .read : .readPrivate
        Task { await Log.timeline.attempt("mark as read") { try await t.markAsRead(receiptType: type) } }
    }

    func loadMore() async {
        guard !loadingMore, !hitStart else { return }
        loadingMore = true
        defer { loadingMore = false; pageTick += 1 }
        // A page that was under way when the SDK dropped the timeline filled one that is gone: page again for the
        // new one (a few times at most, should the drops keep coming).
        for _ in 0..<3 {
            let ticket = paging.ticket
            do {
                let start = try await timeline.paginateBackwards(numEvents: 40)
                pageError = nil; pageFailures = 0
                if paging.finished(ticket: ticket, hitStart: start) {
                    Log.timeline.debug("page loaded: \(self.entries.count, privacy: .public) items, start \(start, privacy: .public)")
                    return
                }
                Log.timeline.notice("timeline dropped while a page loaded; paging the new one")
            } catch {
                // Kept apart from `error` (a failed send): one bad page must not stop paging for good.
                Log.timeline.error("load older messages failed: \(error.localizedDescription, privacy: .public)")
                pageError = "\(error)"; pageFailures += 1
                return
            }
        }
    }

    // MARK: Diffs

    /// What one timeline item contributes, computed once when the item arrives or changes.
    private struct Entry {
        var row: TimelineRow?
        var id = ""
        var eventID: EventOrTransactionId?
        var image: MediaSource?
        var media: MediaSource?
        var thumb: MediaSource?
        var rawReceipts: [(userID: String, timestamp: UInt64?)] = []
    }
    private var entries: [Entry] = []

    private func entry(_ i: TimelineItem) -> Entry {
        var en = Entry(row: Self.row(i, ownID: ownID, profiles: memberProfiles))
        guard let e = i.asEvent() else { return en }
        en.id = "\(i.uniqueId().id)"
        en.eventID = e.eventOrTransactionId
        if case .ready(let dn, _, let av, _, _) = e.senderProfile {
            let name = dn ?? Self.senderName(e.sender, .unavailable)
            memberProfiles[e.sender] = (name: name, avatar: av)
        }
        let receipts = e.readReceipts.compactMap { (userID, receipt) -> (userID: String, timestamp: UInt64?)? in
            guard userID != ownID else { return nil }
            return (userID: userID, timestamp: receipt.timestamp)
        }
        en.rawReceipts = receipts
        if case .msgLike(let m) = e.content, case .message(let c) = m.kind {
            switch c.msgType {
            case .image(let ic): en.image = ic.source; en.media = ic.source
            case .video(let vc): en.media = vc.source; en.thumb = vc.info?.thumbnailSource
            case .audio(let ac): en.media = ac.source
            case .file(let fc): en.media = fc.source
            default: break
            }
        }
        return en
    }

    private func apply(_ diffs: [TimelineDiff]) {
        let before = entries.count
        let oldest = entries.first { !$0.id.isEmpty }?.id
        let out = entries.apply(diffs.map { d -> ListDiff<Entry> in
            switch d {
            case .append(let v): .append(v.map(entry))
            case .clear: .clear
            case .pushFront(let v): .pushFront(entry(v))
            case .pushBack(let v): .pushBack(entry(v))
            case .popFront: .popFront
            case .popBack: .popBack
            case .insert(let i, let v): .insert(Int(i), entry(v))
            case .set(let i, let v): .set(Int(i), entry(v))
            case .remove(let i): .remove(Int(i))
            case .truncate(let n): .truncate(Int(n))
            case .reset(let v): .reset(v.map(entry))
            }
        })
        if out.outOfRange > 0 {
            // Our copy no longer matches the SDK's, and positional diffs cannot mend it: a new listener starts
            // again from the whole timeline.
            Log.timeline.fault("timeline diff out of range (\(out.outOfRange, privacy: .public)); rows no longer match the SDK, listening again")
            if relistens < 3 {
                relistens += 1
                Task { [weak self] in await self?.listen() }
            }
        }
        let ids = Set(entries.lazy.map(\.id).filter { !$0.isEmpty })
        switch paging.received(out, oldestBefore: oldest, idsAfter: ids) {
        case .dropped:
            // A limited sync (more new events than the sync sent): the SDK kept only the newest events and left a
            // gap before them that only paging backwards fills. Without this a room that had reached its start
            // stays "complete" and the messages in the gap never show.
            Log.timeline.notice("SDK dropped the loaded timeline (\(out.cleared ? "clear" : "reset", privacy: .public)): \(before, privacy: .public) → \(self.entries.count, privacy: .public) items; paging back again")
            Task { [weak self] in await self?.loadMore() }
        case .kept:
            if out.reset, before > 0 {
                Log.timeline.debug("timeline sent again whole: \(before, privacy: .public) → \(self.entries.count, privacy: .public) items")
            }
        }
        rebuildRows()
        markRead()
        itemIDs = [:]; imageSources = [:]; mediaSources = [:]; thumbSources = [:]
        for en in entries where !en.id.isEmpty {
            itemIDs[en.id] = en.eventID
            imageSources[en.id] = en.image
            mediaSources[en.id] = en.media
            thumbSources[en.id] = en.thumb
        }
        checkForMissingProfiles()
    }

    private func rebuildRows() {
        rows = entries.compactMap { en in
            guard var r = en.row else { return nil }
            if let id = r.eventID {
                (r.threadReplies, r.threadLatest) = ThreadInfo.merge(replies: r.threadReplies, latest: r.threadLatest,
                                                                     with: threadInfo[id])
            }
            return r
        }
    }

    private func checkForMissingProfiles() {
        let missing = Set(entries.flatMap { $0.rawReceipts.map(\.userID) })
            .subtracting(memberProfiles.keys)
            .subtracting(pendingProfileFetches)
        guard !missing.isEmpty else { return }
        pendingProfileFetches.formUnion(missing)
        Task { [weak self] in
            await self?.fetchMissingProfiles(missing)
        }
    }

    private func fetchMissingProfiles(_ userIDs: Set<String>) async {
        guard let room = try? client.getRoom(roomId: roomID) else { return }
        var updated = false
        for uid in userIDs {
            if let m = try? await room.member(userId: uid) {
                let name = m.displayName ?? Self.senderName(uid, .unavailable)
                memberProfiles[uid] = (name: name, avatar: m.avatarUrl)
                updated = true
            }
        }
        pendingProfileFetches.subtract(userIDs)
        if updated {
            refreshReceipts()
        }
    }

    private func loadRoomMembers() async {
        guard let room = try? client.getRoom(roomId: roomID),
              let it = try? await room.members() else { return }
        var all: [RoomMember] = []
        while let chunk = it.nextChunk(chunkSize: 200), all.count < 500 { all += chunk }
        var updated = false
        for m in all {
            let name = m.displayName ?? Self.senderName(m.userId, .unavailable)
            if memberProfiles[m.userId]?.name != name || memberProfiles[m.userId]?.avatar != m.avatarUrl {
                memberProfiles[m.userId] = (name: name, avatar: m.avatarUrl)
                updated = true
            }
        }
        if updated {
            refreshReceipts()
        }
    }

    private func refreshReceipts() {
        var changed = false
        for i in 0..<entries.count {
            guard !entries[i].rawReceipts.isEmpty else { continue }
            let updated: [ReadReceipt] = entries[i].rawReceipts.map { r in
                let prof = memberProfiles[r.userID]
                let name = prof?.name ?? Self.senderName(r.userID, .unavailable)
                let date = r.timestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) }
                return ReadReceipt(userID: r.userID, displayName: name, avatarURL: prof?.avatar, date: date)
            }.sorted {
                if let d1 = $0.date, let d2 = $1.date { return d1 > d2 }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            if entries[i].row?.readReceipts != updated {
                entries[i].row?.readReceipts = updated
                changed = true
            }
        }
        if changed {
            rebuildRows()
        }
    }

    // MARK: Rows

    static func senderName(_ sender: String, _ profile: ProfileDetails) -> String {
        if case .ready(let dn, _, _, _, _) = profile, let dn { return dn }
        // No display name known (yet): the part of the Matrix ID before the colon reads better than all of it.
        if sender.hasPrefix("@"), let colon = sender.firstIndex(of: ":") { return String(sender[sender.index(after: sender.startIndex)..<colon]) }
        return sender
    }

    struct Described {
        var text: String
        var media: MediaInfo?
        var edited = false
        /// Encrypted and not readable (yet): the text says why.
        var locked = false
    }

    /// The text a message shows, its media, whether it was edited.
    static func describe(_ m: MsgLikeContent) -> Described {
        guard case .message(let c) = m.kind else {
            switch m.kind {
            case .unableToDecrypt(let msg):
                var cause = UtdCause.unknown
                if case .megolmV1AesSha2(_, let c) = msg { cause = c }
                let why = switch cause {
                case .sentBeforeWeJoined: String(localized: "Sent before you joined")
                case .historicalMessageAndBackupIsDisabled: String(localized: "Older message: enter your recovery key to read it")
                case .unsignedDevice, .unknownDevice, .verificationViolation: String(localized: "Sent from an unverified device")
                default: String(localized: "Waiting for the key to decrypt…")
                }
                return Described(text: why, locked: true)
            case .redacted: return Described(text: String(localized: "Message deleted"))
            case .sticker(let body, _, _): return Described(text: "[sticker] " + body)
            case .poll(let q, _, _, _, _, _, _): return Described(text: "[poll] " + q)
            default: return Described(text: String(localized: "Unsupported message"))
            }
        }
        let edited = c.isEdited
        switch c.msgType {
        case .text(let t): return Described(text: t.body, edited: edited)
        case .emote(let t): return Described(text: "* " + t.body, edited: edited)
        case .notice(let t): return Described(text: t.body, edited: edited)
        case .image(let ic):
            return Described(text: ic.caption ?? "", media: MediaInfo(kind: .image, name: ic.filename, size: ic.info?.size,
                                                                      pixels: ic.info.flatMap { i in i.width.flatMap { w in i.height.map { CGSize(width: Double(w), height: Double($0)) } } }), edited: edited)
        case .video(let vc):
            return Described(text: vc.caption ?? "", media: MediaInfo(kind: .video, name: vc.filename, size: vc.info?.size, duration: vc.info?.duration), edited: edited)
        case .audio(let ac):
            return Described(text: ac.caption ?? "", media: MediaInfo(kind: .audio, name: ac.filename, size: ac.info?.size, duration: ac.info?.duration, isVoice: ac.voice != nil), edited: edited)
        case .file(let fc):
            return Described(text: fc.caption ?? "", media: MediaInfo(kind: .file, name: fc.filename, size: fc.info?.size), edited: edited)
        case .location(let l):
            let coords = l.geoUri.replacingOccurrences(of: "geo:", with: "").split(separator: ";").first.map(String.init) ?? ""
            return Described(text: "[📍 \(l.description ?? l.body)](https://maps.apple.com/?ll=\(coords))", edited: edited)
        default: return Described(text: c.body, edited: edited)
        }
    }

    static func isLocked(_ content: TimelineItemContent?) -> Bool {
        if case .msgLike(let m)? = content, case .unableToDecrypt = m.kind { return true }
        return false
    }

    static func summary(of content: TimelineItemContent?) -> String {
        guard case .msgLike(let m)? = content else { return "" }
        let d = describe(m)
        guard let media = d.media else { return d.text }
        let icon = media.kind == .image ? "🖼" : media.kind == .video ? "🎬" : media.kind == .audio ? "🎵" : "📎"
        return icon + " " + (d.text.isEmpty ? media.name : d.text)
    }

    static func row(_ item: TimelineItem, ownID: String, profiles: [String: (name: String, avatar: String?)] = [:]) -> TimelineRow? {
        guard let e = item.asEvent(), case .msgLike(let m) = e.content else { return nil }
        let d = describe(m)
        var eid: String?
        if case .eventId(let x) = e.eventOrTransactionId { eid = x }
        var replies = 0
        var latest: String?
        if let s = m.threadSummary {
            replies = Int(s.numReplies())
            if case .ready(let content, let sender, let profile, _, _) = s.latestEvent() {
                latest = senderName(sender, profile) + ": " + summary(of: content)
            }
        }
        var reply: ReplyPreview?
        if let ir = m.inReplyTo {
            if case .ready(let content, let sender, let profile, _, _) = ir.event() {
                reply = ReplyPreview(sender: senderName(sender, profile), text: summary(of: content), eventID: ir.eventId())
            } else {
                reply = ReplyPreview(sender: "", text: "…", eventID: ir.eventId())
            }
        }
        let chips = e.reactions.map { r in
            ReactionChip(key: r.key, count: r.senders.count, mine: r.senders.contains { $0.senderId == ownID },
                         names: r.senders.map { senderName($0.senderId, .unavailable) })
        }
        let receipts: [ReadReceipt] = e.readReceipts.compactMap { (userID, receipt) in
            guard userID != ownID else { return nil }
            let prof = profiles[userID]
            let name = prof?.name ?? senderName(userID, .unavailable)
            let date = receipt.timestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) }
            return ReadReceipt(userID: userID, displayName: name, avatarURL: prof?.avatar, date: date)
        }.sorted {
            if let d1 = $0.date, let d2 = $1.date { return d1 > d2 }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        return TimelineRow(id: "\(item.uniqueId().id)", sender: senderName(e.sender, e.senderProfile), senderID: e.sender,
                           senderAvatar: { if case .ready(_, _, let u, _, _) = e.senderProfile { return u }; return nil }(),
                           locked: d.locked, text: d.text, isOwn: e.isOwn, date: Date(timeIntervalSince1970: Double(e.timestamp) / 1000),
                           eventID: eid, reactions: chips, isEditable: e.isEditable, isEdited: d.edited, reply: reply,
                           media: d.media, threadRoot: m.threadRoot, threadReplies: replies, threadLatest: latest,
                           readReceipts: receipts)
    }

    // MARK: Actions

    func send(_ text: String) async {
        if !attachments.isEmpty { await sendAttachments(caption: text); return }
        guard !text.isEmpty else { return }
        let content = messageEventContentFromMarkdown(md: text)
        do {
            if let e = editing, let id = itemIDs[e.id] {
                try await timeline.edit(eventOrTransactionId: id, newContent: .roomMessage(content: content))
            } else if let r = replyingTo, let eid = r.eventID {
                _ = try await timeline.sendReply(msg: content, eventId: eid)
            } else {
                _ = try await timeline.send(msg: content)
            }
        } catch { self.error = "\(error)" }
        editing = nil; replyingTo = nil
    }

    /// Send pictures as they are instead of scaled down and re-encoded.
    var sendOriginal = Setting.alwaysHD.isOn()

    func addAttachments(_ items: [Attachment]) { attachments += items }
    func addFiles(_ urls: [URL]) { attachments += urls.compactMap(Attachment.make) }
    func removeAttachment(_ a: Attachment) { attachments.removeAll { $0 == a } }

    /// Each attachment goes out as its own message; the typed text is the caption of the first one, and the reply
    /// target (if any) is the first one's too.
    private func sendAttachments(caption: String) async {
        let batch = attachments
        let reply = replyingTo?.eventID
        attachments = []; replyingTo = nil; editing = nil
        sending = true
        defer { sending = false }
        let limit = (try? await client.getMaxMediaUploadSize()) ?? 0
        let hd = sendOriginal
        sendOriginal = false
        for (i, orig) in batch.enumerated() {
            let a = hd ? orig : (orig.compressed() ?? orig)
            if limit > 0, a.size > limit {
                let fmt = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
                self.error = String(localized: "\(a.url.lastPathComponent) is too large (\(Attachment.formattedSize(a.size))); the server limit is \(fmt).")
                continue
            }
            let text = i == 0 ? caption.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let params = UploadParameters(source: .file(filename: a.url.path), caption: text.isEmpty ? nil : text,
                                          formattedCaption: nil, mentions: nil, inReplyTo: i == 0 ? reply : nil,
                                          extraContentJson: nil)
            do {
                let handle: SendAttachmentJoinHandle
                switch a.kind {
                case .image:
                    handle = try timeline.sendImage(params: params, thumbnailSource: nil, imageInfo: ImageInfo(
                        height: a.height, width: a.width, mimetype: a.mime, size: a.size, thumbnailInfo: nil,
                        thumbnailSource: nil, blurhash: nil, isAnimated: nil))
                case .video:
                    handle = try timeline.sendVideo(params: params, thumbnailSource: nil, videoInfo: VideoInfo(
                        duration: a.duration, height: a.height, width: a.width, mimetype: a.mime, size: a.size,
                        thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil))
                case .audio:
                    handle = try timeline.sendAudio(params: params, audioInfo: AudioInfo(duration: a.duration, size: a.size, mimetype: a.mime))
                case .file:
                    handle = try timeline.sendFile(params: params, fileInfo: FileInfo(
                        mimetype: a.mime, size: a.size, thumbnailInfo: nil, thumbnailSource: nil))
                }
                try await handle.join()
            } catch { self.error = "\(error)" }
        }
    }

    func toggleReaction(_ row: TimelineRow, _ key: String) async {
        guard let id = itemIDs[row.id] else { return }
        await Log.timeline.attempt("toggle reaction") { try await timeline.toggleReaction(itemId: id, key: key) }
        await Log.timeline.attempt("remember emoji") { try await client.addRecentEmoji(emoji: key) }
    }

    func delete(_ row: TimelineRow) async {
        guard let id = itemIDs[row.id] else { return }
        await Log.timeline.attempt("redact") { try await timeline.redactEvent(eventOrTransactionId: id, reason: nil) }
    }

    func pin(_ row: TimelineRow) async {
        guard let id = row.eventID else { return }
        await Log.timeline.attempt("pin") { try await timeline.pinEvent(eventId: id) }
    }

    func unpin(_ row: TimelineRow) async {
        guard let id = row.eventID else { return }
        await Log.timeline.attempt("unpin") { try await timeline.unpinEvent(eventId: id) }
    }

    /// A matrix.to link to this message.
    func permalink(_ row: TimelineRow) -> String? {
        guard let id = row.eventID else { return nil }
        return "https://matrix.to/#/\(roomID)/\(id)"
    }

    func recentEmojis() async -> [String] {
        ((try? await client.getRecentEmojis()) ?? []).map(\.emoji)
    }

    // MARK: Media

    func image(_ row: TimelineRow) async -> NSImage? {
        await thumbnail(row, source: imageSources[row.id])
    }

    func videoThumbnail(_ row: TimelineRow) async -> NSImage? {
        await thumbnail(row, source: thumbSources[row.id] ?? mediaSources[row.id])
    }

    private func thumbnail(_ row: TimelineRow, source: MediaSource?) async -> NSImage? {
        if let hit = imageCache.object(forKey: row.id as NSString) { return hit }
        guard let source, let data = try? await client.getMediaThumbnail(mediaSource: source, width: 480, height: 480),
              let cg = await Task.detached(operation: { Self.downsample(data, maxPixel: 720) }).value else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        imageCache.setObject(img, forKey: row.id as NSString, cost: cg.bytesPerRow * cg.height)
        return img
    }

    /// Decodes straight to display size; servers often send the original instead of a real thumbnail.
    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// The whole picture's bytes, for the viewer and for saving.
    func fullImageData(_ row: TimelineRow) async -> Data? {
        guard let src = imageSources[row.id] else { return nil }
        return await Log.media.attempt("download media") { try await client.getMediaContent(mediaSource: src) }
    }

    /// Downloads a file, video or audio message to the cache and returns where it is.
    func download(_ row: TimelineRow) async -> URL? {
        guard let src = mediaSources[row.id], let media = row.media else { return nil }
        let mime = UTType(filenameExtension: (media.name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        guard let handle = try? await client.getMediaFile(mediaSource: src, filename: media.name, mimeType: mime, useCache: true, tempDir: nil),
              let path = try? handle.path() else { return nil }
        // The handle owns the temporary file; keep a copy under the real name so it opens with the right app.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ElemelekMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(row.id.replacingOccurrences(of: "/", with: "_") + "-" + media.name)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: dest)
        return dest
    }
}
