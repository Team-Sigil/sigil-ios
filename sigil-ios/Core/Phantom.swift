import CryptoKit
import Foundation
import SwiftUI
import UIKit

/// Phantom, over its deeplinks.
///
/// Sigil has no passwords: the wallet proves who you are. Phantom holds the key, so every
/// signature means leaving the app, approving there, and being sent back to `sigil://`
/// with an encrypted reply. Two round trips to connect and sign in, and one more for each
/// thing a guardian signs afterwards.
///
/// Everything Phantom sends back is encrypted to the app's own x25519 key with NaCl box,
/// so a reply can only be read by this install.
@MainActor
@Observable
final class Phantom {
    static let shared = Phantom()

    /// The connected wallet's address, base58. Nil until `connect()` succeeds.
    private(set) var wallet: String?

    /// Phantom's session token for this connection, sent back with every signing request.
    private var session: String?
    /// `crypto_box_beforenm` with Phantom's public key: how replies are read.
    private var sharedKey: Data?

    private var pending: Pending?
    private var cancelOnReturn: Task<Void, Never>?

    private struct Pending {
        let kind: Kind
        let continuation: CheckedContinuation<[String: String], Error>
        enum Kind { case connect, sign }
    }

    // MARK: Identity of this install

    private static let secretAccount = "sigil.phantom.app-secret"
    private static let sessionAccount = "sigil.phantom.session"
    private static let sharedAccount = "sigil.phantom.shared-key"
    private static let walletAccount = "sigil.phantom.wallet"

    /// The app's x25519 keypair. Phantom encrypts to its public half, so it has to outlive
    /// a launch — losing it means every stored session becomes unreadable.
    private var appSecret: Curve25519.KeyAgreement.PrivateKey {
        if let stored = Keychain.read(Self.secretAccount),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: stored) {
            return key
        }
        let fresh = Curve25519.KeyAgreement.PrivateKey()
        _ = try? Keychain.write(fresh.rawRepresentation, account: Self.secretAccount)
        return fresh
    }

    private init() {
        session = Keychain.readString(Self.sessionAccount)
        wallet = Keychain.readString(Self.walletAccount)
        sharedKey = Keychain.read(Self.sharedAccount)
    }

    var isConnected: Bool { wallet != nil && session != nil && sharedKey != nil }

    /// Phantom must be installed; on a device without it the connect link goes nowhere.
    var isAvailable: Bool {
        UIApplication.shared.canOpenURL(URL(string: "phantom://")!)
    }

    // MARK: The two things the app asks Phantom to do

    /// Connects, and returns the wallet address Phantom reports.
    ///
    /// The address is never typed or scanned at sign-in: it comes from Phantom, so the
    /// app can't be pointed at an account the user doesn't control.
    @discardableResult
    func connect() async throws -> String {
        let reply = try await send(
            kind: .connect,
            url: url("connect", [
                "app_url": PhantomConfig.appURL,
                "dapp_encryption_public_key": Base58.encode(
                    [UInt8](appSecret.publicKey.rawRepresentation)
                ),
                "redirect_link": "\(PhantomConfig.scheme)://onConnect",
                "cluster": PhantomConfig.cluster,
            ])
        )
        guard let phantomKey = reply["phantom_encryption_public_key"],
              let nonce = reply["nonce"], let data = reply["data"],
              let peer = Base58.decode(phantomKey),
              let nonceBytes = Base58.decode(nonce),
              let box = Base58.decode(data) else {
            throw PhantomError.badReply
        }
        let shared = try NaCl.sharedKey(
            theirPublicKey: Data(peer), ourSecretKey: appSecret.rawRepresentation
        )
        guard let plain = NaCl.open(Data(box), nonce: Data(nonceBytes), sharedKey: shared),
              let payload = try? JSONDecoder().decode(ConnectPayload.self, from: plain) else {
            throw PhantomError.badReply
        }
        sharedKey = shared
        session = payload.session
        wallet = payload.publicKey
        _ = try? Keychain.write(shared, account: Self.sharedAccount)
        Keychain.write(payload.session, account: Self.sessionAccount)
        Keychain.write(payload.publicKey, account: Self.walletAccount)
        return payload.publicKey
    }

    /// Has Phantom sign the exact text, and returns the base58 signature.
    ///
    /// `display: "utf8"` is what makes Phantom show the readable text rather than bytes,
    /// so the person approves something they can actually read.
    func sign(_ message: String) async throws -> String {
        guard let session, let sharedKey else { throw PhantomError.notConnected }

        let request = SignRequest(
            message: Base58.encode([UInt8](Data(message.utf8))),
            session: session,
            display: "utf8"
        )
        let body = try JSONEncoder().encode(request)
        // A fresh nonce for every request: reusing one with the same key breaks the cipher.
        var nonce = Data(count: 24)
        nonce.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = SecRandomCopyBytes(kSecRandomDefault, 24, base)
        }
        let payload = NaCl.seal(body, nonce: nonce, sharedKey: sharedKey)

        let reply = try await send(
            kind: .sign,
            url: url("signMessage", [
                "dapp_encryption_public_key": Base58.encode(
                    [UInt8](appSecret.publicKey.rawRepresentation)
                ),
                "nonce": Base58.encode([UInt8](nonce)),
                "redirect_link": "\(PhantomConfig.scheme)://onSign",
                "payload": Base58.encode([UInt8](payload)),
            ])
        )
        guard let replyNonce = reply["nonce"], let data = reply["data"],
              let nonceBytes = Base58.decode(replyNonce), let box = Base58.decode(data),
              let plain = NaCl.open(Data(box), nonce: Data(nonceBytes), sharedKey: sharedKey),
              let signed = try? JSONDecoder().decode(SignPayload.self, from: plain) else {
            throw PhantomError.badReply
        }
        return signed.signature
    }

    /// Has Phantom sign a transaction, and returns the signed bytes, base58.
    ///
    /// Phantom shows what the transaction does and signs it, but does **not** submit it:
    /// its `signAndSendTransaction` deeplink was retired (it now answers "This method is
    /// not supported"), and it only ever reached mainnet anyway. So the app broadcasts the
    /// signed bytes to devnet itself — `Devnet.send` — and confirms them there.
    func signTransaction(_ transaction: String) async throws -> String {
        guard let session, let sharedKey else { throw PhantomError.notConnected }

        let body = try JSONSerialization.data(withJSONObject: [
            "transaction": transaction,
            "session": session,
        ])
        var nonce = Data(count: 24)
        nonce.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = SecRandomCopyBytes(kSecRandomDefault, 24, base)
        }
        let payload = NaCl.seal(body, nonce: nonce, sharedKey: sharedKey)

        let reply = try await send(
            kind: .sign,
            url: url("signTransaction", [
                "dapp_encryption_public_key": Base58.encode(
                    [UInt8](appSecret.publicKey.rawRepresentation)
                ),
                "nonce": Base58.encode([UInt8](nonce)),
                "redirect_link": "\(PhantomConfig.scheme)://onApprove",
                "payload": Base58.encode([UInt8](payload)),
            ])
        )
        guard let replyNonce = reply["nonce"], let data = reply["data"],
              let nonceBytes = Base58.decode(replyNonce), let box = Base58.decode(data),
              let plain = NaCl.open(Data(box), nonce: Data(nonceBytes), sharedKey: sharedKey),
              let signed = try? JSONDecoder().decode(SignedTransactionPayload.self, from: plain)
        else {
            throw PhantomError.badReply
        }
        return signed.transaction
    }

    private struct SignedTransactionPayload: Decodable {
        /// The signed, serialized transaction, base58 — not a signature.
        let transaction: String
    }

    /// Forgets this connection. The next sign-in connects again, which is also how you
    /// switch to a different Phantom account.
    func disconnect() {
        wallet = nil
        session = nil
        sharedKey = nil
        Keychain.delete(Self.sessionAccount)
        Keychain.delete(Self.walletAccount)
        Keychain.delete(Self.sharedAccount)
    }

    // MARK: Coming back from Phantom

    /// Called for every `sigil://` the app is opened with.
    func handle(_ url: URL) {
        guard let pending else { return }
        cancelOnReturn?.cancel()
        cancelOnReturn = nil
        self.pending = nil

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var values: [String: String] = [:]
        for item in items { values[item.name] = item.value }

        if let code = values["errorCode"] {
            // 4001 is the user tapping Cancel, which is not a failure worth shouting about.
            let message = values["errorMessage"] ?? "Phantom couldn't do that."
            pending.continuation.resume(
                throwing: code == "4001" ? PhantomError.cancelled : PhantomError.phantom(message)
            )
            return
        }
        pending.continuation.resume(returning: values)
    }

    /// The app coming back to the front without a reply means the person left Phantom
    /// without approving, so the request is dropped rather than spinning forever.
    func appBecameActive() {
        guard pending != nil, cancelOnReturn == nil else { return }
        cancelOnReturn = Task {
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled, let waiting = pending else { return }
            pending = nil
            cancelOnReturn = nil
            waiting.continuation.resume(throwing: PhantomError.cancelled)
        }
    }

    private func send(kind: Pending.Kind, url: URL) async throws -> [String: String] {
        if let existing = pending {
            pending = nil
            existing.continuation.resume(throwing: PhantomError.superseded)
        }
        guard await UIApplication.shared.canOpenURL(url) else { throw PhantomError.notInstalled }
        return try await withCheckedThrowingContinuation { continuation in
            pending = Pending(kind: kind, continuation: continuation)
            Task { await UIApplication.shared.open(url) }
        }
    }

    private func url(_ action: String, _ parameters: [String: String]) -> URL {
        var components = URLComponents(string: "https://phantom.app/ul/v1/\(action)")!
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    private struct ConnectPayload: Decodable {
        let publicKey: String
        let session: String

        enum CodingKeys: String, CodingKey {
            case publicKey = "public_key"
            case session
        }
    }

    private struct SignPayload: Decodable {
        let signature: String
    }

    private struct SignRequest: Encodable {
        let message: String
        let session: String
        let display: String
    }
}

/// Where Phantom is told to send the user back, and which chain to use.
///
/// `appURL`'s host must equal the gateway's `SIWS_DOMAIN`, or Phantom shows a red domain
/// mismatch warning on the sign-in text.
enum PhantomConfig {
    static let appURL = "https://iden.casa"
    static let scheme = "sigil"
    static let cluster = "devnet"
}

enum PhantomError: Error {
    case notInstalled
    case notConnected
    case cancelled
    case superseded
    case badReply
    case phantom(String)

    var readable: String {
        switch self {
        case .notInstalled: "Phantom isn't installed on this device."
        case .notConnected: "Connect your wallet first."
        case .cancelled: "You cancelled that in Phantom."
        case .superseded: "Another request replaced that one."
        case .badReply: "Phantom's reply couldn't be read."
        case .phantom(let message): message
        }
    }
}
