import CryptoKit
import Foundation
import Security

/// Signs the gateway's texts with the user's Solana key.
///
/// Every guardian action that matters — activating a policy, answering a question,
/// freezing — counts only as an ed25519 signature over a fixed text, so this is the one
/// place the app proves who it is.
/// The texts a guardian signs, built exactly as the gateway rebuilds them: UTF-8, `\n`
/// line breaks, no trailing newline. A byte out of place is a refused signature.
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

protocol WalletService {
    /// The Solana address, base58.
    var address: String { get throws }
    /// Signs the exact bytes of `message`; the gateway rebuilds the text and compares.
    func sign(_ message: String) throws -> String
}

/// A key held in the app, standing in for Phantom until the wallet is settled.
///
/// Same curve and encoding as a real wallet (ed25519, base58), so the gateway cannot tell
/// the difference and nothing above this protocol has to change when Phantom arrives.
/// It is **not** a wallet: the key lives in this app's Keychain, there is no approval
/// screen, and it is for devnet only.
final class LocalWallet: WalletService {
    private static let keychainAccount = "sigil.devnet.signing-key"

    /// Loaded once and kept. Without this, a failed Keychain write would mean a fresh key
    /// on every call — the address would belong to one key and the signature to another,
    /// and the gateway would answer "signature does not match the sign-in message".
    private var cached: Curve25519.Signing.PrivateKey?

    private func key() throws -> Curve25519.Signing.PrivateKey {
        if let cached { return cached }
        if let stored = Keychain.read(Self.keychainAccount) {
            let existing = try Curve25519.Signing.PrivateKey(rawRepresentation: stored)
            cached = existing
            return existing
        }
        let fresh = Curve25519.Signing.PrivateKey()
        try? Keychain.write(fresh.rawRepresentation, account: Self.keychainAccount)
        cached = fresh
        return fresh
    }

    var address: String {
        get throws { Base58.encode([UInt8](try key().publicKey.rawRepresentation)) }
    }

    func sign(_ message: String) throws -> String {
        let signature = try key().signature(for: Data(message.utf8))
        return Base58.encode([UInt8](signature))
    }

    /// Forgets the key, so the next sign-in is a different person. Used by sign-out while
    /// this stands in for a wallet; a real wallet would simply disconnect.
    func forget() {
        cached = nil
        Keychain.delete(Self.keychainAccount)
    }
}

/// Small Keychain wrapper for the signing key and the session token.
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
}
