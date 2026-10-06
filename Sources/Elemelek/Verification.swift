import Foundation
import MatrixRustSDK

/// Verifying this session against another one of the user's devices (SAS: compare emoji).
enum VerificationFlow: Equatable {
    case idle
    case requesting            // asking the other device
    case waitingForOther       // request sent, the other device must accept
    case waitingForEmojis      // SAS started
    case emojis([VerifyEmoji]) // compare these on both devices
    case confirming            // we approved, waiting for the other side
    case done
    case failed
}

struct VerifyEmoji: Equatable, Identifiable {
    let id: Int
    let symbol: String
    let name: String
}

final class VerifyStateListener: VerificationStateListener, @unchecked Sendable {
    let handler: @Sendable (VerificationState) -> Void
    init(_ handler: @escaping @Sendable (VerificationState) -> Void) { self.handler = handler }
    func onUpdate(status: VerificationState) { handler(status) }
}

final class VerifyDelegate: SessionVerificationControllerDelegate, @unchecked Sendable {
    let onEvent: @Sendable (Event) -> Void
    enum Event {
        case request(senderId: String, flowId: String)
        case accepted, started, data(SessionVerificationData), failed, cancelled, finished
    }
    init(_ onEvent: @escaping @Sendable (Event) -> Void) { self.onEvent = onEvent }
    func didReceiveVerificationRequest(details: SessionVerificationRequestDetails) {
        onEvent(.request(senderId: details.senderProfile.userId, flowId: details.flowId))
    }
    func didAcceptVerificationRequest() { onEvent(.accepted) }
    func didStartSasVerification() { onEvent(.started) }
    func didReceiveVerificationData(data: SessionVerificationData) { onEvent(.data(data)) }
    func didFail() { onEvent(.failed) }
    func didCancel() { onEvent(.cancelled) }
    func didFinish() { onEvent(.finished) }
}

extension AppModel {
    /// Ask the user's other signed-in device to verify this session.
    func startVerification() async {
        guard let client else { return }
        verification = .requesting
        do {
            let c = try await client.getSessionVerificationController()
            verifyController = c
            let d = VerifyDelegate { [weak self] e in Task { @MainActor in await self?.handle(e) } }
            verifyDelegate = d
            c.setDelegate(delegate: d)
            try await c.requestDeviceVerification()
            if verification == .requesting { verification = .waitingForOther }
        } catch {
            self.error = "\(error)"
            verification = .failed
        }
    }

    private func handle(_ e: VerifyDelegate.Event) async {
        guard let c = verifyController else { return }
        switch e {
        case .request(let sender, let flow):
            // An incoming request from another device: accept it and carry on with SAS.
            do {
                try await c.acknowledgeVerificationRequest(senderId: sender, flowId: flow)
                try await c.acceptVerificationRequest()
            } catch { verification = .failed }
        case .accepted:
            verification = .waitingForEmojis
            do { try await c.startSasVerification() } catch { verification = .failed }
        case .started:
            verification = .waitingForEmojis
        case .data(let data):
            switch data {
            case .emojis(let emojis, _):
                verification = .emojis(emojis.enumerated().map { VerifyEmoji(id: $0.offset, symbol: $0.element.symbol(), name: $0.element.description()) })
            case .decimals:
                verification = .failed
            }
        case .finished:
            verification = .done
            verified = client?.encryption().verificationState() == .verified
        case .failed, .cancelled:
            if verification != .done { verification = .failed }
        }
    }

    func approveVerification() async {
        guard let c = verifyController else { return }
        verification = .confirming
        do { try await c.approveVerification() } catch { verification = .failed }
    }

    func declineVerification() async {
        await Log.session.attempt("decline verification") { try await verifyController?.declineVerification() }
        verification = .idle
    }

    func cancelVerification() async {
        await Log.session.attempt("cancel verification") { try await verifyController?.cancelVerification() }
        verifyController?.setDelegate(delegate: nil)
        verifyController = nil; verifyDelegate = nil
        verification = .idle
    }
}
