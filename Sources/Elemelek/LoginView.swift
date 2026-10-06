import SwiftUI
import AppKit

struct LoginView: View {
    @Environment(AppModel.self) var model
    @State private var server = "matrix.org"
    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @FocusState private var focus: Field?
    private enum Field { case server, user, password }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = switch hour {
        case 5..<12: String(localized: "Good morning")
        case 12..<18: String(localized: "Hello")
        case 18..<23: String(localized: "Good evening")
        default: String(localized: "Good night")
        }
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? hello : "\(hello), \(first)"
    }

    private var canSubmit: Bool {
        !busy && !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !user.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .init(x: 0.5, y: 0.1),
                           startRadius: 10, endRadius: 520).ignoresSafeArea()
            do {
                VStack(spacing: 0) {
                    header
                    card.padding(.top, 20)
                    features.padding(.top, 20)
                    Text("Your password goes only to your own server. Elemelek sends nothing to third parties.")
                        .font(Theme.font(size: 11)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                        .padding(.top, 22)
                }
                .frame(maxWidth: 400)
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 520, minHeight: 820)
        .onAppear { focus = .user }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high).frame(width: 128, height: 128)
            Text("Elemelek")
                .font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
            Text(greeting)
                .font(Theme.font(size: 17, weight: .medium)).foregroundStyle(Theme.dim)
            Text("A native macOS messenger built on the Matrix protocol. Encrypted chats, threads and message search — all working locally on your Mac.")
                .font(Theme.font(size: 13)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Homeserver", hint: "e.g. matrix.org or the address of your own server") {
                TextField("matrix.org", text: $server).kitField().focused($focus, equals: .server)
                    .onSubmit { focus = .user }
            }
            field("Username", hint: nil) {
                TextField("username or @username:server", text: $user).kitField().focused($focus, equals: .user)
                    .onSubmit { focus = .password }
            }
            field("Password", hint: nil) {
                SecureField("••••••••", text: $password).kitField().focused($focus, equals: .password)
                    .onSubmit(submit)
            }
            if let e = model.error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.font(size: 12)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
            }
            Button(action: submit) {
                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small) }
                    (busy ? Text("Logging in…") : Text("Log in")).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(KitButton(prominent: true))
            .keyboardShortcut(.defaultAction).disabled(!canSubmit)
        }
        .padding(20)
        .plate(Theme.panel, radius: Theme.chromeRadius)
    }

    private func field<C: View>(_ title: LocalizedStringKey, hint: LocalizedStringKey?, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Theme.font(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
            content()
            if let hint { Text(hint).font(Theme.font(size: 11)).foregroundStyle(Theme.dim) }
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            feature("lock", "End-to-end encryption", "Full support for encrypted rooms.")
            feature("magnifier", "Local search", "Search encrypted messages too.")
            feature("speech_balloon", "Threads and reactions", "Replies, edits and emoji.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feature(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Pic(name: icon, size: 26).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text(text).font(Theme.font(size: 11)).foregroundStyle(Theme.dim)
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        busy = true
        Task {
            await model.login(server: server.trimmingCharacters(in: .whitespaces),
                              user: user.trimmingCharacters(in: .whitespaces), password: password)
            busy = false
        }
    }
}
