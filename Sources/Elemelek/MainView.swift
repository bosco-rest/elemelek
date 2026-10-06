import SwiftUI
import AppKit

extension View {
    /// Double-click on a bar: the window fills the screen area and goes back, like a title bar does.
    func zoomsWindowOnDoubleClick() -> some View {
        contentShape(Rectangle()).onTapGesture(count: 2) { NSApp.keyWindow?.zoom(nil) }
    }
}

struct MainView: View {
    @Environment(AppModel.self) var model
    @State private var query = ""
    @State private var showSidebar = true
    @State private var showVerify = false
    @State private var roomSheet: RoomSheet?

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Sidebar(query: $query, showVerify: $showVerify, roomSheet: $roomSheet, compact: !showSidebar,
                        expand: { withAnimation(.snappy) { showSidebar = true } })
                    .frame(width: showSidebar ? 280 : 72)
                Rectangle().fill(Theme.hairline).frame(width: 1).ignoresSafeArea()
                DetailView(showSidebar: $showSidebar)
            }
            .ignoresSafeArea(edges: .top)
            .background(Theme.background.ignoresSafeArea())

            if let box = model.lightbox {
                LightboxView(box: box)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(10)
            }
        }
        .animation(.spring(duration: 0.28, bounce: 0.12), value: model.lightbox?.row.id)
        .frame(minWidth: 820, minHeight: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.markCurrentRead() }
        .sheet(isPresented: $showVerify) { VerifySheet(isPresented: $showVerify) }
        .sheet(item: $roomSheet) { which in
            switch which {
            case .direct: NewDirectSheet(sheet: $roomSheet)
            case .create: CreateRoomSheet(sheet: $roomSheet)
            case .join: JoinRoomSheet(sheet: $roomSheet)
            }
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Environment(AppModel.self) var model
    @Binding var query: String
    @Binding var showVerify: Bool
    @Binding var roomSheet: RoomSheet?
    /// Folded to a column of avatars; the name shows on hover.
    var compact = false
    var expand: () -> Void = {}
    @State private var leaving: RoomEntry?
    @State private var settingsFor: String?
    @State private var confirmLogout = false

    private func roomRow(_ r: RoomEntry) -> some View {
        RoomRow(name: r.name, avatarURL: r.avatarURL, unread: r.hasUnread, count: r.notifications,
                mentioned: r.mentioned, selected: model.selectedRoomID == r.id, compact: compact) {
            Task { await model.select(r.id) }
        }
        .contextMenu {
            Button("Room settings…") { settingsFor = r.id }
            Divider()
            Button("Leave room", role: .destructive) { leaving = r }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The traffic lights float over this strip; it drags the window and double-click zooms it.
            HStack(spacing: 8) {
                Spacer()
                if !compact { newMenu }
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(Color.clear.contentShape(Rectangle()).zoomsWindowOnDoubleClick().gesture(WindowDragGesture()))
            .padding(.bottom, 4)

            if compact {
                VStack(spacing: 6) {
                    newMenu
                    IconButton(pic: "magnifyingglass", help: "Search messages", size: 32) { expand() }
                }.padding(.bottom, 6)
            } else {
                searchField
            }
            roomList
            footer
        }
        .background(Theme.sidebar.ignoresSafeArea())
        .sheet(isPresented: Binding(get: { settingsFor != nil }, set: { if !$0 { settingsFor = nil } })) {
            if let id = settingsFor { RoomSettingsSheet(roomID: id) }
        }
        .confirmationDialog("Log out of Elemelek?", isPresented: $confirmLogout) {
            Button("Log out", role: .destructive) { Task { await model.logout() } }
        } message: { Text("You will need your password to sign in again.") }
        .confirmationDialog("Leave this room?", isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
                            presenting: leaving) { r in
            Button("Leave \(r.name)", role: .destructive) { Task { await model.leaveRoom(r.id) } }
        }
    }

    private var newMenu: some View {
                Menu {
                    Button("New message") { roomSheet = .direct }
                    Button("New room") { roomSheet = .create }
                    Button("Join a room") { roomSheet = .join }
                } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 15, weight: .regular)).foregroundStyle(Theme.dim)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("New conversation")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Pic(name: "magnifier", size: 14).opacity(0.8)
            TextField("Search messages", text: $query).textFieldStyle(.plain).font(Theme.font(size: 13))
                .onChange(of: query) { _, q in Task { await model.search(q) } }
            if !query.isEmpty {
                Button { query = "" } label: { Pic(name: "cross_mark", size: 12) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Capsule().fill(Theme.wash(0.07)))
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private func section(_ title: String.LocalizationValue) -> some View {
        Group {
            if compact { Rectangle().fill(Theme.hairline).frame(width: 28, height: 1).padding(.vertical, 6) }
            else { SectionLabel(title) }
        }
    }

    private var roomList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if query.isEmpty || compact {
                    let invites = model.rooms.filter { $0.invited && !$0.isSpace }
                    if !compact {
                        if !invites.isEmpty { SectionLabel("Invitations") }
                        ForEach(invites) { r in InviteRow(room: r) }
                    }
                    let visible = model.rooms.filter { !$0.isSpace && !$0.invited }
                    let dms = visible.filter(\.isDirect)
                    let rest = visible.filter { !$0.isDirect }
                    if !dms.isEmpty && !compact { section("Direct messages") }
                    ForEach(dms) { r in roomRow(r) }
                    if !dms.isEmpty && !rest.isEmpty { section("Rooms") }
                    ForEach(rest) { r in roomRow(r) }
                } else if model.searchHits.isEmpty {
                    Text("No results").font(Theme.font(size: 12)).foregroundStyle(Theme.dim).padding(.top, 20)
                } else {
                    ForEach(model.searchHits) { h in
                        HitRow(hit: h) { query = ""; Task { await model.select(h.roomID) } }
                            .onAppear { if h.id == model.searchHits.last?.id { Task { await model.loadMoreSearch() } } }
                    }
                }
            }.padding(.horizontal, 8).padding(.vertical, 4)
        }
        .scrollIndicators(compact ? .hidden : .automatic)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if !compact, model.indexTotal > 0, model.indexDone < model.indexTotal {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Indexing messages… \(model.indexDone)/\(model.indexTotal)")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.dim)
                    Spacer()
                }.padding(.horizontal, 14).padding(.vertical, 6)
            }
            HStack {
                if !compact { Spacer().frame(width: 2) }
                AccountMenu(verified: model.verified, verify: { showVerify = true }) { confirmLogout = true }
                if !compact { Spacer() }
            }.padding(.horizontal, 10).padding(.vertical, 8)
        }
    }
}

private struct InviteRow: View {
    @Environment(AppModel.self) var model
    let room: RoomEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Avatar(name: room.name, url: room.avatarURL, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(room.name).font(Theme.font(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if let who = room.inviter {
                        Text("Invited by \(who)").font(Theme.font(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button("Accept") { Task { await model.acceptInvite(room.id) } }.buttonStyle(.borderedProminent).controlSize(.small)
                Button("Decline") { Task { await model.declineInvite(room.id) } }.controlSize(.small)
            }.padding(.leading, 40)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.10)))
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String.LocalizationValue) { self.text = String(localized: text) }
    var body: some View {
        Text(verbatim: text).font(Theme.font(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
    }
}

private struct RoomRow: View {
    let name: String
    var avatarURL: String?
    var unread = false
    var count: UInt64 = 0
    var mentioned = false
    let selected: Bool
    var compact = false
    let action: () -> Void
    @State private var hovering = false
    @State private var showName = false
    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    /// The avatar alone, with the unread state as a badge on its corner and the name in a popover on hover.
    private var compactBody: some View {
        Button(action: action) {
            Avatar(name: name, url: avatarURL, size: 36)
                .overlay(alignment: .topTrailing) {
                    Group {
                        if mentioned {
                            Text("@").font(Theme.font(size: 10, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 16, height: 16).background(Circle().fill(Theme.red))
                        } else if count > 0 {
                            Text(count > 99 ? "99+" : "\(count)").font(Theme.font(size: 10, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16).background(Capsule().fill(Theme.accent))
                        } else if unread {
                            Circle().fill(Theme.dim).frame(width: 9, height: 9)
                        }
                    }
                    .overlay(Capsule().strokeBorder(Theme.sidebar, lineWidth: 2).padding(-2))
                    .offset(x: 4, y: -3)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.20) : Theme.wash(hovering ? 0.06 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if h {
                Task { try? await Task.sleep(for: .milliseconds(350)); if hovering { showName = true } }
            } else { showName = false }
        }
        .popover(isPresented: $showName, arrowEdge: .trailing) {
            Text(name).font(Theme.font(size: 13, weight: unread ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .accessibilityLabel(name)
    }

    private var fullBody: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(name: name, url: avatarURL, size: 30)
                Text(name).font(Theme.font(size: 13, weight: unread ? .semibold : .regular))
                    .foregroundStyle(unread || selected ? Theme.text : Theme.text.opacity(0.75)).lineLimit(1)
                Spacer(minLength: 0)
                if mentioned {
                    Text("@").font(Theme.font(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18).background(Circle().fill(Theme.red))
                        .help("You were mentioned")
                }
                if count > 0 {
                    Text(count > 999 ? "999+" : "\(count)").font(Theme.font(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.accent))
                } else if unread && !mentioned {
                    Circle().fill(Theme.dim).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.20) : Theme.wash(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

private struct HitRow: View {
    let hit: SearchHit
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(hit.roomName) · \(hit.sender)").font(Theme.font(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                Text(hit.text).font(Theme.font(size: 13)).foregroundStyle(Theme.text).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.wash(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

/// One quiet button; the account, settings and logging out live in its menu.
private struct AccountMenu: View {
    @Environment(AppModel.self) var model
    var verified = true
    var verify: () -> Void = {}
    let logout: () -> Void
    var body: some View {
        let me = (try? model.client?.userId()) ?? ""
        Menu {
            Text(me)
            if !verified { Button("Verify this session…", action: verify) }
            Divider()
            SettingsLink { Text("Settings…") }
            Button("Log out…", role: .destructive, action: logout)
        } label: {
            Image(systemName: "person.crop.circle").font(.system(size: 17)).foregroundStyle(Theme.dim)
                .frame(width: 28, height: 28).contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if !verified { Circle().fill(Theme.orange).frame(width: 7, height: 7).offset(x: -2, y: 3) }
                }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Account")
    }
}
