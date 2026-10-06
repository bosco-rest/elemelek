import SwiftUI

/// The right-hand panel: every thread of the room, or one thread open.
struct SidePanelView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        VStack(spacing: 0) {
            switch model.sidePanel {
            case .none:
                EmptyView()
            case .threads:
                ThreadListPanel()
            case .thread:
                ThreadPanel()
            }
        }
        .background(Theme.background)
    }
}

private struct PanelHeader: View {
    let title: LocalizedStringKey
    var back: (() -> Void)?
    let close: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            if let back { IconButton(pic: "right_arrow_curving_left", help: "Back", action: back) }
            Pic(name: "thread", size: 18)
            Text(title).font(Theme.font(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            IconButton(pic: "cross_mark", help: "Close", action: close)
        }
        .padding(.horizontal, 12).frame(height: 48)
        .zoomsWindowOnDoubleClick().gesture(WindowDragGesture())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct ThreadListPanel: View {
    @Environment(AppModel.self) var model
    var body: some View {
        PanelHeader(title: "Threads") { model.hideSidePanel() }
        if model.threads.isEmpty {
            VStack(spacing: 10) {
                Pic(name: "thread", size: 44).opacity(0.9)
                Text("No threads in this room yet").font(Theme.font(size: 13)).foregroundStyle(Theme.dim)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.threads) { t in
                        ThreadRow(entry: t) { Task { await model.openThread(t.id) } }
                    }
                }.padding(8)
            }
        }
    }
}

private struct ThreadRow: View {
    @Environment(AppModel.self) var model
    let entry: ThreadEntry
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Avatar(name: entry.rootSender, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.rootSender).font(Theme.font(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.tint(for: entry.rootSender))
                    // The thread list keeps the event as first fetched; the room timeline retries decryption, so
                    // a root that is readable there is shown from there.
                    if entry.rootLocked, let r = model.timeline?.rows.first(where: { $0.eventID == entry.id }), !r.locked {
                        Text(r.text).font(Theme.font(size: 13)).foregroundStyle(Theme.text).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else if entry.rootLocked {
                        LockedLine(text: entry.rootText)
                    } else {
                        Text(entry.rootText).font(Theme.font(size: 13)).foregroundStyle(Theme.text).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 6) {
                        Text("Replies: \(entry.replies)").font(Theme.font(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                        if let l = entry.latest {
                            Text(l).font(Theme.font(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.wash(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

private struct ThreadPanel: View {
    @Environment(AppModel.self) var model
    var body: some View {
        PanelHeader(title: "Thread", back: { Task { await model.showThreads() } }) { model.closeThread() }
        if let tl = model.thread {
            TimelineList(tl: tl, inThread: true)
            Composer(tl: tl, inThread: true)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
