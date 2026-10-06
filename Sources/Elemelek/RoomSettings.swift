import SwiftUI
import MatrixRustSDK

/// One room's details: picture, name, topic, notifications, members, leaving.
struct RoomSettingsSheet: View {
    @Environment(AppModel.self) var model
    let roomID: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var topic = ""
    @State private var avatar: String?
    @State private var mode: Mode = .default
    @State private var members: [RoomMember] = []
    @State private var memberCount: UInt64 = 0
    @State private var busy = false
    @State private var pickingEmoji = false
    @State private var confirmLeave = false
    @State private var error: String?

    enum Mode: Hashable { case `default`, all, mentions, mute }

    private var room: Room? { model.roomObject(roomID) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Avatar(name: name, url: avatar, size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            Menu("Picture") {
                                Button("Choose…") { if let d = Picture.pickSquareJPEG() { upload(d, "image/jpeg") } }
                                Button("Choose an emoji…") { pickingEmoji = true }
                                if avatar != nil {
                                    Button("Remove", role: .destructive) {
                                        Task { await Log.sync.attempt("remove room picture") { try await room?.removeAvatar() }; avatar = nil }
                                    }
                                }
                            }.fixedSize()
                            if busy { ProgressView().controlSize(.small) }
                        }
                    }
                    TextField("Name", text: $name)
                    TextField("Topic", text: $topic, axis: .vertical).lineLimit(1...4)
                }
                Section {
                    Picker("Notify me about", selection: $mode) {
                        Text("Default").tag(Mode.default)
                        Text("All messages").tag(Mode.all)
                        Text("Mentions only").tag(Mode.mentions)
                        Text("Nothing").tag(Mode.mute)
                    }
                }
                Section("Members (\(memberCount))") {
                    ForEach(members, id: \.userId) { m in
                        HStack(spacing: 10) {
                            Avatar(name: m.displayName ?? m.userId, url: m.avatarUrl, size: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(m.displayName ?? m.userId)
                                if m.displayName != nil {
                                    Text(m.userId).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if !role(m).isEmpty {
                                Text(role(m)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .formStyle(.grouped)
            HStack {
                Button("Leave room…", role: .destructive) { confirmLeave = true }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }.keyboardShortcut(.defaultAction)
            }.padding(16)
        }
        .frame(width: 460, height: 600)
        .task { await load() }
        .sheet(isPresented: $pickingEmoji) {
            EmojiPicture { hex in pickingEmoji = false; if let hex, let d = Picture.emoji(hex) { upload(d, "image/png") } }
        }
        .confirmationDialog("Leave this room?", isPresented: $confirmLeave) {
            Button("Leave \(name)", role: .destructive) {
                dismiss(); Task { await model.leaveRoom(roomID) }
            }
        }
    }

    private func role(_ m: RoomMember) -> String {
        let p = m.powerLevel.number
        return p >= 100 ? String(localized: "Admin") : p >= 50 ? String(localized: "Moderator") : ""
    }

    private func load() async {
        guard let room else { return }
        name = room.displayName() ?? ""
        topic = room.topic() ?? ""
        avatar = room.avatarUrl()
        memberCount = room.joinedMembersCount()
        if let c = model.client {
            let enc = await room.isEncrypted()
            if let s = try? await c.getNotificationSettings().getRoomNotificationSettings(
                roomId: roomID, isEncrypted: enc, isOneToOne: model.rooms.first { $0.id == roomID }?.isDirect ?? false) {
                let m: Mode = switch s.mode {
                    case .allMessages: .all
                    case .mentionsAndKeywordsOnly: .mentions
                    case .mute: .mute
                }
                mode = s.isDefault ? .default : m
            }
        }
        if let it = try? await room.members() {
            var all: [RoomMember] = []
            while let chunk = it.nextChunk(chunkSize: 200), all.count < 500 { all += chunk }
            members = all.filter { $0.membership == .join }
                .sorted { a, b in
                    a.powerLevel.number != b.powerLevel.number ? a.powerLevel.number > b.powerLevel.number
                        : (a.displayName ?? a.userId).localizedCaseInsensitiveCompare(b.displayName ?? b.userId) == .orderedAscending
                }
        }
    }

    private func save() async {
        guard let room else { return }
        error = nil
        do {
            if name != (room.displayName() ?? "") { try await room.setName(name: name) }
            if topic != (room.topic() ?? "") { try await room.setTopic(topic: topic) }
            if let s = await model.client?.getNotificationSettings() {
                switch mode {
                case .default: try await s.restoreDefaultRoomNotificationMode(roomId: roomID)
                case .all: try await s.setRoomNotificationMode(roomId: roomID, mode: .allMessages)
                case .mentions: try await s.setRoomNotificationMode(roomId: roomID, mode: .mentionsAndKeywordsOnly)
                case .mute: try await s.setRoomNotificationMode(roomId: roomID, mode: .mute)
                }
            }
            dismiss()
        } catch {
            self.error = String(localized: "You may not have permission to change this room.")
        }
    }

    private func upload(_ data: Data, _ mime: String) {
        busy = true
        Task {
            do { try await room?.uploadAvatar(mimeType: mime, data: data, mediaInfo: nil); avatar = room?.avatarUrl() }
            catch { self.error = String(localized: "You may not have permission to change this room.") }
            busy = false
        }
    }
}

private extension PowerLevel {
    var number: Int64 { if case .value(let v) = self { return v }; return Int64.max }
}
