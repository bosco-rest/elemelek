import SwiftUI

// MARK: - Verification

struct VerifySheet: View {
    @Environment(AppModel.self) var model
    @Binding var isPresented: Bool
    @State private var useKey = false
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Pic(name: model.verification == .done ? "check_mark_button" : "shield", size: 30)
                Text("Verify this session").font(Theme.font(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
            }
            content
        }
        .padding(24).frame(width: 440).background(Theme.background)
        .onDisappear { Task { if model.verification != .done { await model.cancelVerification() } } }
    }

    @ViewBuilder private var content: some View {
        switch model.verification {
        case .idle:
            if useKey { keyForm } else { chooser }
        case .requesting, .waitingForOther:
            progress("Accept the request on your other device — in another Matrix app.")
            HStack { Spacer(); Button("Cancel") { Task { await model.cancelVerification() } }.buttonStyle(KitButton()) }
        case .waitingForEmojis:
            progress("Starting verification…")
        case .emojis(let emojis):
            Text("Compare these emoji with the ones on your other device.")
                .font(Theme.font(size: 13)).foregroundStyle(Theme.dim)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(emojis) { e in
                    VStack(spacing: 4) {
                        SASEmoji(symbol: e.symbol, size: 36)
                        Text(e.name).font(Theme.font(size: 10)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .plate(Theme.panel, radius: 10)
                }
            }
            HStack {
                Spacer()
                Button("They don't match") { Task { await model.declineVerification() } }.buttonStyle(KitButton(tint: Theme.red))
                Button("They match") { Task { await model.approveVerification() } }
                    .buttonStyle(KitButton(prominent: true)).keyboardShortcut(.defaultAction)
            }
        case .confirming:
            progress("Waiting for the other device…")
        case .done:
            Text("This session is verified.").font(Theme.font(size: 13)).foregroundStyle(Theme.dim)
            HStack { Spacer(); Button("Done") { isPresented = false }.buttonStyle(KitButton(prominent: true)).keyboardShortcut(.defaultAction) }
        case .failed:
            Text("Verification failed or was cancelled.").font(Theme.font(size: 13)).foregroundStyle(Theme.red)
            if let e = model.error { Text(e).font(Theme.font(size: 11)).foregroundStyle(Theme.dim).lineLimit(3) }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.buttonStyle(KitButton())
                Button("Try again") { Task { await model.startVerification() } }.buttonStyle(KitButton(prominent: true))
            }
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm it's you to read your encrypted messages.").font(Theme.font(size: 13)).foregroundStyle(Theme.dim)
            Button { Task { await model.startVerification() } } label: {
                HStack(spacing: 8) {
                    Pic(name: "mobile_phone", size: 18)
                    Text("Verify with another device")
                }.frame(maxWidth: .infinity)
            }.buttonStyle(KitButton(prominent: true)).keyboardShortcut(.defaultAction)
            Button { useKey = true } label: {
                HStack(spacing: 8) {
                    Pic(name: "key", size: 18)
                    Text("Use recovery key instead")
                }.frame(maxWidth: .infinity)
            }.buttonStyle(KitButton())
            HStack { Spacer(); Button("Cancel") { isPresented = false }.buttonStyle(KitButton()) }
        }
    }

    private var keyForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("Paste your recovery key", text: $key).kitField()
            if let m = model.recoveryMessage { Text(m).font(Theme.font(size: 12)).foregroundStyle(Theme.red) }
            HStack {
                Button("Back") { useKey = false }.buttonStyle(KitButton())
                Spacer()
                Button("Unlock") {
                    Task { await model.recover(key); key = ""; if model.verified { isPresented = false } }
                }.buttonStyle(KitButton(prominent: true)).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func progress(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).font(Theme.font(size: 13)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
        }
    }
}
