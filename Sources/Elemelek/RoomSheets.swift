import SwiftUI
import MatrixRustSDK

enum RoomSheet: String, Identifiable {
    case direct, create, join
    var id: String { rawValue }
}

/// One small form shell shared by the three room sheets.
private struct SheetFrame<Content: View>: View {
    let title: LocalizedStringKey
    let busy: Bool
    let error: String?
    @ViewBuilder var content: Content
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(Theme.font(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                IconButton(pic: "cross_mark", help: "Close", size: 28, action: close)
            }
            content
            if let error {
                Text(error).font(Theme.font(size: 12)).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .padding(18).frame(width: 400).background(Theme.background)
    }
}

struct NewDirectSheet: View {
    @Environment(AppModel.self) var model
    @Binding var sheet: RoomSheet?
    @State private var term = ""
    @State private var results: [UserProfile] = []
    @State private var busy = false
    @State private var error: String?

    private func start(_ id: String) {
        busy = true; error = nil
        Task {
            error = await model.startDirect(id)
            busy = false
            if error == nil { sheet = nil }
        }
    }

    var body: some View {
        SheetFrame(title: "New message", busy: busy, error: error, content: {
            TextField("Name or @user:server", text: $term).textFieldStyle(.roundedBorder)
                .onSubmit { if term.hasPrefix("@"), term.contains(":") { start(term) } }
                .task(id: term) {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    results = await model.searchUsers(term)
                }
            ScrollView {
                LazyVStack(spacing: 2) {
                    if term.hasPrefix("@"), term.contains(":"), !results.contains(where: { $0.userId == term }) {
                        UserRow(name: term, id: term) { start(term) }
                    }
                    ForEach(results, id: \.userId) { u in
                        UserRow(name: u.displayName ?? u.userId, id: u.userId) { start(u.userId) }
                    }
                }
            }.frame(height: 240)
        }, close: { sheet = nil })
    }
}

private struct UserRow: View {
    let name: String
    let id: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(name: name, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(Theme.font(size: 13)).foregroundStyle(Theme.text).lineLimit(1)
                    if name != id { Text(id).font(Theme.font(size: 11)).foregroundStyle(Theme.dim).lineLimit(1) }
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.wash(hovering ? 0.07 : 0)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
    }
}

struct CreateRoomSheet: View {
    @Environment(AppModel.self) var model
    @Binding var sheet: RoomSheet?
    @State private var name = ""
    @State private var topic = ""
    @State private var isPublic = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        SheetFrame(title: "New room", busy: busy, error: error, content: {
            TextField("Room name", text: $name).textFieldStyle(.roundedBorder)
            TextField("Topic (optional)", text: $topic).textFieldStyle(.roundedBorder)
            Toggle("Public room (not encrypted)", isOn: $isPublic)
            HStack {
                Spacer()
                Button("Create") {
                    busy = true; error = nil
                    Task {
                        error = await model.createRoom(name: name.trimmingCharacters(in: .whitespaces), topic: topic, isPublic: isPublic)
                        busy = false
                        if error == nil { sheet = nil }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }, close: { sheet = nil })
    }
}

struct JoinRoomSheet: View {
    @Environment(AppModel.self) var model
    @Binding var sheet: RoomSheet?
    @State private var target = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        SheetFrame(title: "Join a room", busy: busy, error: error, content: {
            TextField("#room:server or !id:server", text: $target).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Join") {
                    busy = true; error = nil
                    Task {
                        error = await model.joinRoom(target)
                        busy = false
                        if error == nil { sheet = nil }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(busy || target.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }, close: { sheet = nil })
    }
}
