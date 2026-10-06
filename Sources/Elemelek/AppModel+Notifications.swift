import AppKit
import ElemelekCore
import UserNotifications
import MatrixRustSDK

final class TypingSink: TypingNotificationsListener, @unchecked Sendable {
    let onTyping: @Sendable ([String]) -> Void
    init(_ f: @escaping @Sendable ([String]) -> Void) { onTyping = f }
    func call(typingUserIds: [String]) { onTyping(typingUserIds) }
}

/// Opens the room of a clicked notification and shows banners even while the app is in front but on another room.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    let open: @Sendable (String) -> Void
    init(open: @escaping @Sendable (String) -> Void) { self.open = open }
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        if let id = r.notification.request.content.userInfo["room"] as? String { open(id) }
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension AppModel {
    func setUpNotifications() {
        guard notifDelegate == nil else { return }
        let d = NotificationDelegate { [weak self] id in Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            await self?.select(id)
        } }
        notifDelegate = d
        let c = UNUserNotificationCenter.current()
        c.delegate = d
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// A banner for a room whose notification count went up while you are not looking at it. The first counts
    /// seen after launch are the baseline, so nothing fires for what was already unread.
    func notifyAboutNew() {
        for e in rooms where !e.isSpace {
            let n = e.notifications
            defer { notifiedCounts[e.id] = n }
            guard let before = notifiedCounts[e.id], n > before else { continue }
            if NSApp.isActive, selectedRoomID == e.id { continue }
            if !Setting.banners.isOn() { continue }
            guard let room = roomObjects.first(where: { $0.id() == e.id }) else { continue }
            let name = e.name, id = e.id, mention = e.highlights > 0
            Task {
                var body = String(localized: "New message")
                if case .remote(_, let sender, let own, let profile, let content) = await room.latestEvent(), !own {
                    var who = sender
                    if case .ready(let dn, _, _, _, _) = profile, let dn { who = dn }
                    body = "\(who): \(TimelineModel.summary(of: content))"
                }
                let c = UNMutableNotificationContent()
                c.title = name; c.body = body
                if Setting.notificationSound.isOn() { c.sound = .default }
                c.userInfo = ["room": id]
                if mention { c.interruptionLevel = .timeSensitive }
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            }
        }
    }

    /// Tells the room you are typing (called as the draft changes); refreshed every few seconds, cleared when empty.
    func typingChanged(_ on: Bool) {
        guard let room = currentRoom, Setting.typingNotices.isOn() else { return }
        if on {
            if let t = typingSent, Date().timeIntervalSince(t) < 4 { return }
            typingSent = Date()
            Task { await Log.sync.attempt("typing notice") { try await room.typingNotice(isTyping: true) } }
        } else if typingSent != nil {
            typingSent = nil
            Task { await Log.sync.attempt("typing notice") { try await room.typingNotice(isTyping: false) } }
        }
    }

    func watchTyping(_ room: Room) {
        typingNames = []
        let me = (try? client?.userId()) ?? ""
        typingHandle = room.subscribeToTypingNotifications(listener: TypingSink { [weak self] ids in
            Task { @MainActor in
                var names: [String] = []
                for id in ids where id != me {
                    let dn = (try? await room.memberDisplayName(userId: id)) ?? nil
                    names.append(dn ?? String(id.dropFirst().prefix { $0 != ":" }))
                }
                self?.typingNames = names
            }
        })
    }
}
