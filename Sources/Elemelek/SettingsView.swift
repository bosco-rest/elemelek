import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MatrixRustSDK
import ElemelekCore

/// Preferences, in the usual macOS tabs. Few on purpose: only what someone would actually change.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AccountSettings().tabItem { Label("Account", systemImage: "person.crop.circle") }
            NotificationSettingsView().tabItem { Label("Notifications", systemImage: "bell.badge") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Setting.linkPreviews.key) private var linkPreviews = Setting.linkPreviews.defaultValue
    @AppStorage(Setting.alwaysHD.key) private var alwaysHD = Setting.alwaysHD.defaultValue
    var body: some View {
        Form {
            Section {
                Toggle("Show link previews", isOn: $linkPreviews)
                Text("Previews are fetched on this Mac, never through your homeserver.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Send images in original quality", isOn: $alwaysHD)
                Text("Otherwise images are scaled down to 2048 pixels before sending.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).fixedSize(horizontal: false, vertical: true)
    }
}

private struct AccountSettings: View {
    @Environment(AppModel.self) var model
    @State private var name = ""
    @State private var saved = ""
    @State private var confirmLogout = false
    @State private var busy = false
    @State private var pickingAnimal = false
    var body: some View {
        let me = (try? model.client?.userId()) ?? ""
        Form {
            Section {
                HStack(spacing: 12) {
                    Avatar(name: me, url: model.myAvatar, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(saved.isEmpty ? me : saved).font(.headline)
                        Text(me).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Menu("Picture") {
                        Button("Choose…") { pickPicture() }
                        Button("Choose an emoji…") { pickingAnimal = true }
                        if model.myAvatar != nil {
                            Button("Remove", role: .destructive) {
                                Task { await Log.session.attempt("remove picture") { try await model.client?.removeAvatar() }; model.myAvatar = nil }
                            }
                        }
                    }.fixedSize()
                }
            }
            Section {
                TextField("Display name", text: $name)
                    .onSubmit { save() }
                HStack {
                    Spacer()
                    Button("Save") { save() }.disabled(name.isEmpty || name == saved)
                }
            }
            Section {
                HStack {
                    Text("Sign out of this Mac. Encrypted history needs your recovery key afterwards.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Log out…", role: .destructive) { confirmLogout = true }
                }
            }
        }
        .formStyle(.grouped).fixedSize(horizontal: false, vertical: true)
        .task {
            saved = (try? await model.client?.displayName()) ?? ""
            name = saved
        }
        .sheet(isPresented: $pickingAnimal) {
            EmojiPicture { hex in pickingAnimal = false; if let hex { useEmoji(hex) } }
        }
        .confirmationDialog("Log out of Elemelek?", isPresented: $confirmLogout) {
            Button("Log out", role: .destructive) { Task { await model.logout() } }
        } message: { Text("You will need your password to sign in again.") }
    }
    private func useEmoji(_ hex: String) {
        if let png = Picture.emoji(hex) { upload(png, mime: "image/png") }
    }

    private func upload(_ data: Data, mime: String) {
        busy = true
        Task {
            await Log.session.attempt("upload picture") { try await model.client?.uploadAvatar(mimeType: mime, data: data) }
            model.myAvatar = await Log.session.attempt("load picture") { try await model.client?.avatarUrl() } ?? nil
            busy = false
        }
    }

    private func pickPicture() {
        if let jpeg = Picture.pickSquareJPEG() { upload(jpeg, mime: "image/jpeg") }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            await Log.session.attempt("set display name") { try await model.client?.setDisplayName(name: n) }
            saved = n
        }
    }
}

private struct NotificationSettingsView: View {
    @Environment(AppModel.self) var model
    @AppStorage(Setting.banners.key) private var banners = Setting.banners.defaultValue
    @AppStorage(Setting.notificationSound.key) private var sound = Setting.notificationSound.defaultValue
    @State private var groups: RoomNotificationMode = .allMessages
    @State private var direct: RoomNotificationMode = .allMessages
    @State private var settings: NotificationSettings?
    var body: some View {
        Form {
            Section {
                Toggle("Show banners", isOn: $banners)
                Toggle("Play a sound", isOn: $sound).disabled(!banners)
            }
            Section("Notify me about") {
                Picker("Direct messages", selection: $direct) { modes }
                Picker("Rooms", selection: $groups) { modes }
            }
        }
        .formStyle(.grouped).fixedSize(horizontal: false, vertical: true)
        .task {
            guard let c = model.client else { return }
            let s = await c.getNotificationSettings()
            settings = s
            direct = await s.getDefaultRoomNotificationMode(isEncrypted: true, isOneToOne: true)
            groups = await s.getDefaultRoomNotificationMode(isEncrypted: true, isOneToOne: false)
        }
        .onChange(of: direct) { _, m in apply(m, oneToOne: true) }
        .onChange(of: groups) { _, m in apply(m, oneToOne: false) }
    }
    @ViewBuilder private var modes: some View {
        Text("All messages").tag(RoomNotificationMode.allMessages)
        Text("Mentions only").tag(RoomNotificationMode.mentionsAndKeywordsOnly)
        Text("Nothing").tag(RoomNotificationMode.mute)
    }
    /// The server keeps separate defaults for encrypted and plain rooms; one choice sets both.
    private func apply(_ m: RoomNotificationMode, oneToOne: Bool) {
        guard let s = settings else { return }
        Task {
            for enc in [true, false] {
                await Log.session.attempt("set notification mode") { try await s.setDefaultRoomNotificationMode(isEncrypted: enc, isOneToOne: oneToOne, mode: m) }
            }
        }
    }
}

private struct PrivacySettings: View {
    @Environment(AppModel.self) var model
    @AppStorage(Setting.readReceipts.key) private var readReceipts = Setting.readReceipts.defaultValue
    @AppStorage(Setting.showReadReceipts.key) private var showReadReceipts = Setting.showReadReceipts.defaultValue
    @AppStorage(ReadReceiptStyle.key) private var readReceiptStyle = ReadReceiptStyle.defaultValue.rawValue
    @AppStorage(Setting.typingNotices.key) private var typing = Setting.typingNotices.defaultValue
    @State private var ignored: [String] = []
    var body: some View {
        Form {
            Section {
                Toggle("Send read receipts", isOn: $readReceipts)
                Toggle("Show read receipts in channels", isOn: $showReadReceipts)
                if showReadReceipts {
                    Picker("Display style", selection: $readReceiptStyle) {
                        ForEach(ReadReceiptStyle.allCases, id: \.rawValue) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                }
                Toggle("Show when I'm typing", isOn: $typing)
            }
            Section("Blocked people") {
                if ignored.isEmpty {
                    Text("Nobody is blocked.").foregroundStyle(.secondary)
                }
                ForEach(ignored, id: \.self) { id in
                    HStack {
                        Avatar(name: id, size: 22)
                        Text(id)
                        Spacer()
                        Button("Unblock") {
                            Task {
                                await Log.session.attempt("unignore") { try await model.client?.unignoreUser(userId: id) }
                                ignored.removeAll { $0 == id }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped).fixedSize(horizontal: false, vertical: true)
        .task { ignored = (try? await model.client?.ignoredUsers()) ?? [] }
    }
}

/// Every Fluent emoji, searchable by name and keywords, to pick one as your picture.
struct EmojiPicture: View {
    struct Entry: Decodable, Identifiable { let h: String; let n: String; let k: [String]; let g: String; var id: String { h } }
    static let all: [Entry] = {
        guard let u = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: "Emoji"),
              let d = try? Data(contentsOf: u) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: d)) ?? []
    }()
    let done: (String?) -> Void
    @State private var query = ""
    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = q.isEmpty ? Self.all : Self.all.filter { e in
            e.n.lowercased().contains(q) || e.k.contains { $0.lowercased().contains(q) } || e.g.lowercased().contains(q)
        }
        VStack(spacing: 12) {
            TextField("Search emoji", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 6), count: 9), spacing: 6) {
                    ForEach(shown) { e in
                        Button { done(e.h) } label: {
                            ZStack {
                                Circle().fill(Theme.tint(for: e.h).opacity(0.3))
                                if let img = Pics.image("Emoji", e.h) {
                                    Image(nsImage: img).resizable().scaledToFit().padding(9)
                                }
                            }.frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain).help(e.n)
                    }
                }.padding(4)
                if shown.isEmpty { Text("No results").foregroundStyle(.secondary).padding(.top, 40) }
            }.frame(height: 360)
            HStack { Spacer(); Button("Cancel") { done(nil) }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 520)
    }
}
