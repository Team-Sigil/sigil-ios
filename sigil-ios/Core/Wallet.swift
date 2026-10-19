import CryptoKit
import Foundation
import Security

/// The texts a guardian signs, built exactly as the gateway rebuilds them: UTF-8, `\n`
/// line breaks, no trailing newline. A byte out of place is a refused signature.
///
/// Mirrors `contracts/signing.py`. The server never accepts a client-built message — it
/// rebuilds the text from its own records and compares — so these must match it exactly.
enum SignedMessage {
    static func registerDependent(wallet: String, tokenAccount: String, nonce: String) -> String {
        """
        FinGuard:register-dependent
        family:new
        dependent_wallet:\(wallet)
        dependent_token_account:\(tokenAccount)
        nonce:\(nonce)
        """
    }

    static func activatePolicy(family: String, version: Int, hash: String, nonce: String) -> String {
        """
        FinGuard:activate-policy
        family:\(family)
        version:\(version)
        hash:\(hash)
        nonce:\(nonce)
        """
    }

    static func answerQuestion(
        family: String, question: String, approve: Bool, amount: Units?, nonce: String
    ) -> String {
        """
        FinGuard:answer-question
        family:\(family)
        question:\(question)
        decision:\(approve ? "approve" : "deny")
        amount_units:\(amount.map { String($0.raw) } ?? "none")
        nonce:\(nonce)
        """
    }

    static func freeze(family: String, frozen: Bool, nonce: String) -> String {
        """
        FinGuard:freeze
        family:\(family)
        frozen:\(frozen)
        nonce:\(nonce)
        """
    }
}

/// Signs the gateway's texts with the user's Solana key.
///
/// Every act that matters — signing in, activating a policy, answering a question,
/// freezing — counts only as an ed25519 signature over a fixed text, so this is the one
/// place the app proves who it is.
///
/// Signing is `async` because the real wallet is another app: each signature leaves Sigil,
/// is approved in Phantom, and comes back through `sigil://`.
@MainActor
protocol WalletService {
    /// The connected address, base58. Nil before connecting.
    var address: String? { get }
    /// Connects to the wallet and returns the address it reports.
    @discardableResult
    func connect() async throws -> String
    /// Signs the exact bytes of `message`; the gateway rebuilds the text and compares.
    func sign(_ message: String) async throws -> String
    func disconnect()
}

/// The real wallet: Phantom, over its deeplinks.
@MainActor
struct PhantomWallet: WalletService {
    var address: String? { Phantom.shared.wallet }

    @discardableResult
    func connect() async throws -> String {
        if let existing = Phantom.shared.wallet, Phantom.shared.isConnected { return existing }
        return try await Phantom.shared.connect()
    }

    func sign(_ message: String) async throws -> String {
        if !Phantom.shared.isConnected { _ = try await Phantom.shared.connect() }
        return try await Phantom.shared.sign(message)
    }

    func disconnect() {
        Phantom.shared.disconnect()
    }
}

/// A key held in this app, for running on the simulator, where Phantom cannot be installed.
///
/// Same curve and encoding as a real wallet (ed25519, base58), so the gateway cannot tell
/// the difference. It is **not** a wallet: the key lives in this app's Keychain and there
/// is no approval screen, so it is only ever reached with the `-localWallet` launch
/// argument and never on a device someone is actually using.
///
/// One key per role, so one simulator can play guardian and dependent in turn.
@MainActor
final class LocalWallet: WalletService {
    let role: Role

    init(role: Role) {
        self.role = role
    }

    private var keychainAccount: String { "sigil.devnet.signing-key.\(role.rawValue)" }

    /// Loaded once and kept. Without this a failed Keychain write would mean a fresh key on
    /// every call: the address would belong to one key and the signature to another, and the
    /// gateway would answer "signature does not match the sign-in message".
    private var cached: Curve25519.Signing.PrivateKey?

    private func key() throws -> Curve25519.Signing.PrivateKey {
        if let cached { return cached }
        if let stored = Keychain.read(keychainAccount),
           let existing = try? Curve25519.Signing.PrivateKey(rawRepresentation: stored) {
            cached = existing
            return existing
        }
        let fresh = Curve25519.Signing.PrivateKey()
        _ = try? Keychain.write(fresh.rawRepresentation, account: keychainAccount)
        cached = fresh
        return fresh
    }

    var address: String? {
        try? Base58.encode([UInt8](key().publicKey.rawRepresentation))
    }

    @discardableResult
    func connect() async throws -> String {
        guard let address else { throw PhantomError.badReply }
        return address
    }

    func sign(_ message: String) async throws -> String {
        let signature = try key().signature(for: Data(message.utf8))
        return Base58.encode([UInt8](signature))
    }

    /// Forgets the key, so the next sign-in is a different person.
    func disconnect() {
        cached = nil
        Keychain.delete(keychainAccount)
    }

    /// This device's address for a role, without signing anything.
    static func address(of role: Role) -> String? {
        LocalWallet(role: role).address
    }

    /// Only with `-localWallet`: on a real device the wallet is always Phantom.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-localWallet")
    }
}

/// The aUSD associated token account for a wallet.
///
/// On Solana a wallet holds each token in its own account, whose address is derived from
/// the wallet and the mint — it is never typed, and never chosen by us. The same
/// derivation gives the dependent's destination and the guardian's reservoir.
enum TokenAccount {
    static let mint = "7UoVXbKmrWYbkQasNBmNZUWNh4EDZusM7fwHc3EngsqS"
    static let tokenProgram = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    static let associatedTokenProgram = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"

    /// The associated token account of `wallet` for aUSD.
    static func of(wallet: String) -> String? {
        guard let owner = Base58.decode(wallet),
              owner.count == 32,
              let program = Base58.decode(tokenProgram),
              let mintBytes = Base58.decode(mint),
              let ataProgram = Base58.decode(associatedTokenProgram) else { return nil }
        return findProgramAddress(
            seeds: [owner, program, mintBytes], program: ataProgram
        )
    }

    /// Solana's `findProgramAddress`: hash the seeds with a decreasing bump until the
    /// result is **not** a point on the ed25519 curve, which is what makes it an address
    /// no private key can control.
    private static func findProgramAddress(seeds: [[UInt8]], program: [UInt8]) -> String? {
        for bump in stride(from: 255, through: 0, by: -1) {
            var hasher = SHA256()
            for seed in seeds { hasher.update(data: Data(seed)) }
            hasher.update(data: Data([UInt8(bump)]))
            hasher.update(data: Data(program))
            hasher.update(data: Data("ProgramDerivedAddress".utf8))
            let candidate = [UInt8](hasher.finalize())
            if !Ed25519.isOnCurve(candidate) {
                return Base58.encode(candidate)
            }
        }
        return nil
    }
}

/// Small Keychain wrapper for the signing keys and the session token.
enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "casa.iden.sigil",
            kSecAttrAccount as String: account,
        ]
    }

    static func read(_ account: String) -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    @discardableResult
    static func write(_ data: Data, account: String) throws -> Bool {
        delete(account)
        var request = query(account)
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    static func readString(_ account: String) -> String? {
        read(account).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func write(_ string: String, account: String) {
        _ = try? write(Data(string.utf8), account: account)
    }
}
