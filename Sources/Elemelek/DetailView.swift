import SwiftUI
import AppKit
import ElemelekCore

struct DetailView: View {
    @Environment(AppModel.self) var model
    @Binding var showSidebar: Bool

    private var roomName: String { model.rooms.first { $0.id == model.selectedRoomID }?.name ?? "" }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                if let tl = model.timeline {
                    TimelineList(tl: tl, inThread: false)
                    TypingLine(names: model.typingNames)
                    Composer(tl: tl, inThread: false)
                } else {
                    ContentUnavailableView("Select a room", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Pick a conversation on the left, or start a new one."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
                }
            }
            if model.sidePanel != .none {
                Rectangle().fill(Theme.hairline).frame(width: 1)
                SidePanelView().frame(width: 390).transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy(duration: 0.22), value: model.sidePanel)
    }

    @State private var roomSettings: String?

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(pic: "sidebar.left", help: "Toggle sidebar") { withAnimation(.snappy) { showSidebar.toggle() } }
            if model.selectedRoomID != nil {
                Avatar(name: roomName, url: model.rooms.first { $0.id == model.selectedRoomID }?.avatarURL, size: 26)
                Text(roomName).font(Theme.font(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
            }
            Spacer()
            if let id = model.selectedRoomID {
                IconButton(pic: "info.circle", help: "Room settings") { roomSettings = id }
                IconButton(pic: "thread", help: "Threads") {
                    Task { if model.sidePanel == .threads { model.hideSidePanel() } else { await model.showThreads() } }
                }
            }
        }
        .padding(.leading, 14).padding(.trailing, 14)
        .frame(height: 40)
        .background(Theme.background)
        .zoomsWindowOnDoubleClick().gesture(WindowDragGesture())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .sheet(isPresented: Binding(get: { roomSettings != nil }, set: { if !$0 { roomSettings = nil } })) {
            if let id = roomSettings { RoomSettingsSheet(roomID: id) }
        }
    }
}

// MARK: - Timeline

struct TimelineList: View {
    @Bindable var tl: TimelineModel
    let inThread: Bool
    @State private var position = ScrollPosition(idType: String.self)
    @State private var nearTop = false
    @State private var pageAnchor: String?

    /// Lazy, so only rows near the viewport hold views and layers; pictures reserve their size up front
    /// so rows keep their height while loading, and the bottom anchor holds.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                top
                ForEach(Array(tl.rows.enumerated()), id: \.element.id) { i, r in
                    let first = i == 0 || tl.rows[i - 1].sender != r.sender
                    MessageRow(tl: tl, row: r, showHeader: first, inThread: inThread)
                        .padding(.top, first ? 14 : 2)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, inThread ? 14 : 20).padding(.bottom, 12)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .background(Theme.background)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y < 300 } action: { nearTop = $1 }
        .task(id: PageKey(nearTop: nearTop, tick: tl.pageTick)) {
            // Let the jump back to the anchor land first, so the offset says where the reader really is.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, nearTop, tl.error == nil, !tl.hitStart else { return }
            pageAnchor = tl.rows.first?.id
            await tl.loadMore()
        }
        // Older messages land above, a moment after the page call returns. Keep the row that was on top in
        // place, so the spinner leaves the screen and the next page waits for the reader to scroll up again.
        .onChange(of: tl.rows.first?.id) { _, first in
            guard let a = pageAnchor, first != a else { return }
            pageAnchor = nil
            position.scrollTo(id: a, anchor: .top)
        }
    }

    private struct PageKey: Equatable { var nearTop: Bool; var tick: Int }

    @ViewBuilder private var top: some View {
        if tl.hitStart {
            Text("Start of the conversation").font(Theme.font(size: 11)).foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 14)
        }
    }
}

struct MessageRow: View {
    @Environment(AppModel.self) var model
    let tl: TimelineModel
    let row: TimelineRow
    let showHeader: Bool
    let inThread: Bool
    @AppStorage(Setting.linkPreviews.key) private var linkPreviews = Setting.linkPreviews.defaultValue
    @State private var hovering = false
    @State private var showPicker = false
    @State private var confirmDelete = false

    /// A message from someone else that names you: by Matrix ID, or the pill link to it.
    private var mentionsMe: Bool {
        guard !row.isOwn, let me = try? model.client?.userId() else { return false }
        return row.text.localizedCaseInsensitiveContains(me)
            || row.text.localizedCaseInsensitiveContains("@" + me.dropFirst().prefix { $0 != ":" })
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showHeader { Avatar(name: row.sender, url: row.senderAvatar, size: 34) } else { Color.clear.frame(width: 34, height: 1) }
            VStack(alignment: .leading, spacing: 3) {
                if showHeader {
                    HStack(spacing: 8) {
                        Text(row.sender).font(Theme.font(size: 13, weight: .semibold))
                            .foregroundStyle(row.isOwn ? Theme.accent : Theme.tint(for: row.sender))
                        Text(row.date.map { Self.time.string(from: $0) } ?? "")
                            .font(Theme.font(size: 11)).foregroundStyle(Theme.dim)
                    }
                }
                if let r = row.reply { ReplyQuote(reply: r) }
                if let media = row.media { MediaView(tl: tl, row: row, media: media) }
                if row.locked {
                    LockedLine(text: row.text)
                } else if !row.text.isEmpty {
                    MarkdownText(text: row.text)
                    if row.isEdited {
                        Text("(edited)").font(Theme.font(size: 11)).foregroundStyle(Theme.dim)
                    }
                }
                if linkPreviews { let links = LinkFinder.all(in: row.text); if !links.isEmpty { LinkPreviewCard(urls: links).padding(.top, 2) } }
                if !row.reactions.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(row.reactions) { c in ReactionPill(chip: c) { Task { await tl.toggleReaction(row, c.key) } } }
                    }.padding(.top, 2)
                }
                if !inThread, row.threadReplies > 0, let id = row.eventID {
                    ThreadChip(count: row.threadReplies, latest: row.threadLatest) { Task { await model.openThread(id) } }
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.wash(hovering ? 0.035 : 0)))
        .background(alignment: .leading) {
            if mentionsMe {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.orange.opacity(0.12))
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.orange).frame(width: 3) }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering || showPicker { actionBar.padding(.trailing, 8).offset(y: -14).transition(.opacity) }
        }
        .onHover { hovering = $0 }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu { menuItems }
        .confirmationDialog("Delete this message?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await tl.delete(row) } }
        } message: { Text("This can't be undone.") }
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 0) {
            ForEach(["👍", "❤️", "😂"], id: \.self) { e in
                Button { Task { await tl.toggleReaction(row, e) } } label: {
                    Text(e).font(.system(size: 15)).frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            IconButton(pic: "smiling_face", help: "React", size: 28) { showPicker = true }
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    EmojiPickerLoader(tl: tl) { e in showPicker = false; Task { await tl.toggleReaction(row, e) } }
                }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 16).padding(.horizontal, 3)
            IconButton(pic: "right_arrow_curving_left", help: "Reply", size: 28) { tl.replyingTo = row; tl.editing = nil }
            if !inThread, let id = row.eventID {
                IconButton(pic: "thread", help: "Reply in thread", size: 28) { Task { await model.openThread(id) } }
            }
            if row.isOwn && row.isEditable {
                IconButton(pic: "pencil", help: "Edit", size: 28) { tl.editing = row; tl.replyingTo = nil }
            }
            Menu { menuItems } label: {
                Text("•••").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.dim).frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).help("More")
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .chrome(radius: 12)
    }

    @ViewBuilder private var menuItems: some View {
        Button("Reply") { tl.replyingTo = row; tl.editing = nil }
        if !inThread, let id = row.eventID { Button("Reply in thread") { Task { await model.openThread(id) } } }
        if row.isOwn && row.isEditable { Button("Edit") { tl.editing = row; tl.replyingTo = nil } }
        Divider()
        Button("Copy text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.text, forType: .string) }
        if let link = tl.permalink(row) {
            Button("Copy link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string) }
        }
        if row.eventID != nil {
            Button("Pin") { Task { await tl.pin(row) } }
            Button("Unpin") { Task { await tl.unpin(row) } }
        }
        if row.isOwn { Divider(); Button("Delete", role: .destructive) { confirmDelete = true } }
    }
}

private struct EmojiPickerLoader: View {
    let tl: TimelineModel
    let onPick: (String) -> Void
    @State private var recent: [String] = []
    var body: some View {
        EmojiPicker(recent: recent, onPick: onPick).task { recent = Array(await tl.recentEmojis().prefix(16)) }
    }
}

private struct ReactionPill: View {
    let chip: ReactionChip
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(chip.key).font(.system(size: 13))
                Text("\(chip.count)").font(Theme.font(size: 12, weight: chip.mine ? .semibold : .regular))
                    .foregroundStyle(chip.mine ? Theme.accent : Theme.dim)
            }
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(chip.mine ? Theme.accent.opacity(hovering ? 0.28 : 0.20) : Theme.wash(hovering ? 0.12 : 0.07)))
            .overlay(Capsule().strokeBorder(chip.mine ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .help(chip.names.joined(separator: ", "))
    }
}

private struct ReplyQuote: View {
    let reply: ReplyPreview
    var body: some View {
        HStack(spacing: 8) {
            Pic(name: "right_arrow_curving_left", size: 13).opacity(0.7)
            Rectangle().fill(Theme.accent.opacity(0.6)).frame(width: 2, height: 16)
            if !reply.sender.isEmpty {
                Text(reply.sender).font(Theme.font(size: 12, weight: .semibold)).foregroundStyle(Theme.tint(for: reply.sender))
            }
            Text(reply.text).font(Theme.font(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
        }
    }
}

// MARK: - Media

private struct MediaView: View {
    let tl: TimelineModel
    let row: TimelineRow
    let media: MediaInfo
    var body: some View {
        switch media.kind {
        case .image: ThumbView(row: row, tl: tl, pixels: media.pixels)
        case .video: VideoCard(tl: tl, row: row, media: media)
        case .audio, .file: FileCard(tl: tl, row: row, media: media)
        }
    }
}

private struct VideoCard: View {
    let tl: TimelineModel
    let row: TimelineRow
    let media: MediaInfo
    @State private var thumb: NSImage?
    @State private var busy = false
    var body: some View {
        Button { open() } label: {
            ZStack {
                if let thumb {
                    Image(nsImage: thumb).resizable().scaledToFill().frame(width: 320, height: 200).clipped()
                } else {
                    Rectangle().fill(Theme.wash(0.08)).frame(width: 320, height: 200)
                }
                Circle().fill(.black.opacity(0.55)).frame(width: 54, height: 54)
                    .overlay(busy ? AnyView(ProgressView().controlSize(.small).tint(.white))
                                  : AnyView(Text("▶").font(.system(size: 22)).foregroundStyle(.white).offset(x: 2)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(media.name + (media.duration.map { " · " + Self.dur($0) } ?? ""))
                    .font(Theme.font(size: 11)).foregroundStyle(.white).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.5), in: Capsule()).padding(8)
            }
        }
        .buttonStyle(.plain)
        .task(id: row.id) { thumb = await tl.videoThumbnail(row) }
    }
    private func open() {
        busy = true
        Task { if let u = await tl.download(row) { NSWorkspace.shared.open(u) }; busy = false }
    }
    static func dur(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
}

private struct FileCard: View {
    let tl: TimelineModel
    let row: TimelineRow
    let media: MediaInfo
    @State private var busy = false
    @State private var hovering = false
    var body: some View {
        Button { open() } label: {
            HStack(spacing: 10) {
                Pic(name: media.kind == .audio ? "megaphone" : "paperclip", size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.isVoice ? String(localized: "Voice message") : media.name)
                        .font(Theme.font(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(detail).font(Theme.font(size: 11)).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
                if busy { ProgressView().controlSize(.small) }
            }
            .padding(10).frame(width: 300)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.wash(hovering ? 0.09 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
    private var detail: String {
        [media.size.map(Attachment.formattedSize), media.duration.map(VideoCard.dur)].compactMap { $0 }.joined(separator: " · ")
    }
    private func open() {
        busy = true
        Task { if let u = await tl.download(row) { NSWorkspace.shared.open(u) }; busy = false }
    }
}

private struct ThreadChip: View {
    let count: Int
    let latest: String?
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Pic(name: "thread", size: 16)
                Text("Replies: \(count)").font(Theme.font(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                if let latest {
                    Text(latest).font(Theme.font(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Theme.accent.opacity(hovering ? 0.20 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

struct ThumbView: View {
    @Environment(AppModel.self) var model
    let row: TimelineRow
    let tl: TimelineModel
    var pixels: CGSize? = nil
    @State private var image: NSImage?
    @State private var hovering = false

    /// The box the picture gets, known up front when the sender gave its size, so the row never changes height.
    private var box: CGSize? {
        guard let p = pixels ?? SizeMemo.sizes[row.id], p.width > 0, p.height > 0 else { return nil }
        let s = min(360 / p.width, 360 / p.height, 1)
        return CGSize(width: max(p.width * s, 40), height: max(p.height * s, 40))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: box?.width, height: box?.height)
                    .frame(maxWidth: 360, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
                    .scaleEffect(hovering ? 1.01 : 1)
                    .animation(.spring(duration: 0.2), value: hovering)
                    .onHover { hovering = $0; if $0 { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                    .onTapGesture { model.lightbox = Lightbox(row: row, model: tl) }
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Theme.wash(0.06))
                    .frame(width: box?.width ?? 200, height: box?.height ?? 130)
                    .overlay(ProgressView().controlSize(.small))
            }
        }.task(id: row.id) {
            image = await tl.image(row)
            if pixels == nil, let s = image?.size { SizeMemo.sizes[row.id] = s }
        }
    }
}

/// Sizes of pictures and previews once they have been laid out, so a row that scrolls away and comes back
/// reserves the same space before its content loads again.
@MainActor enum SizeMemo {
    static var sizes: [String: CGSize] = [:]
}

// MARK: - Composer

private struct TypingLine: View {
    let names: [String]
    var text: String {
        switch names.count {
        case 0: return ""
        case 1: return String(localized: "\(names[0]) is typing…")
        case 2: return String(localized: "\(names[0]) and \(names[1]) are typing…")
        default: return String(localized: "Several people are typing…")
        }
    }
    var body: some View {
        Text(text).font(Theme.font(size: 11)).foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading).padding(.horizontal, 22)
            .background(Theme.background)
    }
}

struct Composer: View {
    @Environment(AppModel.self) var model
    @Bindable var tl: TimelineModel
    let inThread: Bool
    @State private var draft = ""
    @State private var dropTargeted = false
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tl.attachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let r = tl.replyingTo ?? tl.editing {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 3, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((tl.editing != nil ? String(localized: "Editing: ") : String(localized: "Replying to: ")) + r.sender)
                            .font(Theme.font(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                        Text(r.text.isEmpty ? (r.media?.name ?? "") : r.text).font(Theme.font(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    Spacer()
                    IconButton(pic: "cross_mark", help: "Cancel", size: 24) {
                        tl.replyingTo = nil; tl.editing = nil; draft = ""
                    }
                }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
            }
            if !tl.attachments.isEmpty { AttachmentStrip(tl: tl).padding(.horizontal, 12).padding(.top, 10) }
            HStack(alignment: .bottom, spacing: 6) {
                IconButton(pic: "paperclip", help: "Attach files", size: 32) { pick() }
                TextField(LocalizedStringKey(placeholder), text: $draft, axis: .vertical)
                    .textFieldStyle(.plain).font(Theme.font(size: 14)).lineLimit(1...8)
                    .padding(.vertical, 6)
                    .focused($focused)
                    .onSubmit(send)
                if tl.sending { ProgressView().controlSize(.small).frame(width: 32, height: 32) }
                Button(action: send) {
                    Pic(name: "outbox_tray", size: 18)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(canSend ? Theme.accent.opacity(0.9) : Theme.wash(0.08)))
                }
                .buttonStyle(.plain).disabled(!canSend)
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
        }
        .chrome()
        .overlay(RoundedRectangle(cornerRadius: Theme.chromeRadius, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: dropTargeted ? 2 : 0))
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 6)
        .background(Theme.background)
        .dropDestination(for: URL.self) { urls, _ in tl.addFiles(urls); return !urls.isEmpty } isTargeted: { dropTargeted = $0 }
        .onChange(of: draft) { _, d in if !inThread { model.typingChanged(!d.isEmpty) } }
        .onChange(of: tl.editing) { _, e in if let e { draft = e.text } }
        .onChange(of: focused) { _, f in if f { PasteRouter.current = { tl.addAttachments($0) } } }
        .onAppear { PasteRouter.install() }
    }

    private var placeholder: String {
        if !tl.attachments.isEmpty { return "Add a caption…" }
        return inThread ? "Reply in thread…" : "Write a message"
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { tl.addFiles(panel.urls) }
    }

    private func send() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        draft = ""
        Task { await tl.send(t) }
    }
}

/// What is about to be sent, as chips above the field; the cross takes one out.
private struct AttachmentStrip: View {
    @Bindable var tl: TimelineModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tl.attachments) { a in
                    HStack(spacing: 8) {
                        if let t = a.thumbnail {
                            Image(nsImage: t).resizable().scaledToFill().frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        } else {
                            Pic(name: a.kind == .audio ? "megaphone" : "paperclip", size: 26).frame(width: 40, height: 40)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).font(Theme.font(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1).frame(maxWidth: 160, alignment: .leading)
                            Text(Attachment.formattedSize(a.size)).font(Theme.font(size: 11)).foregroundStyle(Theme.dim)
                        }
                        IconButton(pic: "cross_mark", help: "Remove", size: 22) { tl.removeAttachment(a) }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.wash(0.07)))
                }
            }
        }
        if tl.attachments.contains(where: { $0.kind == .image }) {
            Toggle("Send in original quality (HD)", isOn: $tl.sendOriginal)
                .toggleStyle(.checkbox).font(Theme.font(size: 12)).foregroundStyle(Theme.dim)
        }
        }
    }
}

/// A message that cannot be read yet: quiet, in the secondary colour, with the reason.
struct LockedLine: View {
    let text: String
    var body: some View {
        Label { Text(text).italic() } icon: { Image(systemName: "lock.fill").imageScale(.small) }
            .font(Theme.font(size: 12)).foregroundStyle(Theme.dim)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.wash(0.05)))
            .help("Elemelek asks your other sessions and the key backup for the key; the message updates by itself when it arrives.")
    }
}
