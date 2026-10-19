import Foundation

/// A read-only look at Solana devnet, for the one thing the gateway doesn't check.
///
/// The gateway takes the token account it is given. If that account doesn't exist on
/// chain, registration succeeds and every payment to that dependent fails later, so the
/// app checks before asking anyone to sign anything.
enum Devnet {
    static let rpc = URL(string: "https://api.devnet.solana.com")!

    /// What the chain says about a token account's delegation: the last word on whether
    /// the agent may spend, whatever the app or the gateway believe.
    struct Delegation {
        let delegate: String?
        let delegatedAmount: UInt64
        let balance: UInt64
    }

    /// A blockhash is only good for about 150 slots — a minute or so — and the clock starts
    /// the moment the node hands it over, so this is fetched immediately before the wallet
    /// is opened, and again on every retry.
    ///
    /// `confirmed`, not `finalized`: a finalized hash is already some thirty slots old when
    /// it arrives, which spends a quarter of its life before the guardian has even seen
    /// Phantom. The approval happens in another app, so every spare second counts.
    static func latestBlockhash() async -> String? {
        let result = await call("getLatestBlockhash", [["commitment": "confirmed"]])
        let value = (result?["value"] as? [String: Any])
        return value?["blockhash"] as? String
    }

    /// What devnet made of a transaction the app submitted.
    enum Sent {
        case accepted(signature: String)
        /// The blockhash died while the guardian was in Phantom. Nothing is wrong with the
        /// transaction itself: signing it again on a fresh blockhash is all it takes.
        case expired
        /// Devnet looked at it and said no, in its own words.
        case rejected(String)
        case unreachable
    }

    /// Broadcasts a transaction the wallet has already signed.
    ///
    /// Phantom only signs — its `signAndSendTransaction` deeplink was retired, and it only
    /// ever reached mainnet — so submitting is the app's job. Preflight is left on, so a
    /// transaction the token program would refuse comes back as a reason rather than as a
    /// signature that never lands.
    static func send(signedTransaction base58: String) async -> Sent {
        guard let raw = Base58.decode(base58), !raw.isEmpty else {
            return .rejected("Your wallet returned something the app couldn't read.")
        }
        // base64 rather than base58: the RPC deprecated base58 for this one call.
        let encoded = Data(raw).base64EncodedString()
        guard let json = await rpc("sendTransaction", [
            encoded, ["encoding": "base64", "preflightCommitment": "confirmed"],
        ]) else {
            return .unreachable
        }
        if let signature = json["result"] as? String { return .accepted(signature: signature) }
        let message = (json["error"] as? [String: Any])?["message"] as? String
        // Told apart from a real refusal: it is the one failure worth simply retrying.
        if message?.localizedCaseInsensitiveContains("blockhash not found") == true {
            return .expired
        }
        return .rejected(message ?? "Devnet wouldn't accept it.")
    }

    /// Waits for the network to accept the transaction. Returns nil if it never lands.
    static func confirm(signature: String, within seconds: Double = 45) async -> Bool? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let result = await call("getSignatureStatuses", [[signature]])
            if let value = (result?["value"] as? [Any])?.first as? [String: Any] {
                if value["err"] is [String: Any] { return false }
                if let status = value["confirmationStatus"] as? String,
                   status == "confirmed" || status == "finalized" {
                    return true
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
        return nil
    }

    /// Reads the delegation straight from the token account.
    static func delegation(of tokenAccount: String) async -> Delegation? {
        let result = await call(
            "getAccountInfo", [tokenAccount, ["encoding": "jsonParsed"]]
        )
        guard let value = result?["value"] as? [String: Any],
              let data = value["data"] as? [String: Any],
              let parsed = data["parsed"] as? [String: Any],
              let info = parsed["info"] as? [String: Any] else { return nil }
        let delegated = (info["delegatedAmount"] as? [String: Any])?["amount"] as? String
        let balance = (info["tokenAmount"] as? [String: Any])?["amount"] as? String
        return Delegation(
            delegate: info["delegate"] as? String,
            delegatedAmount: UInt64(delegated ?? "0") ?? 0,
            balance: UInt64(balance ?? "0") ?? 0
        )
    }

    private static func call(_ method: String, _ params: [Any]) async -> [String: Any]? {
        await rpc(method, params)?["result"] as? [String: Any]
    }

    /// The whole JSON-RPC envelope, so a caller can read `error` as well as `result`.
    /// Nil means devnet was never reached — which must not be read as a refusal.
    private static func rpc(_ method: String, _ params: [Any]) async -> [String: Any]? {
        var request = URLRequest(url: rpc, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
        ])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    /// `true` when the account exists, `false` when it doesn't, and `nil` when devnet
    /// couldn't be reached — which must not be mistaken for "doesn't exist".
    static func accountExists(_ pubkey: String) async -> Bool? {
        var request = URLRequest(url: rpc, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getAccountInfo",
            "params": [pubkey, ["encoding": "jsonParsed"]],
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // {"result": {"value": null}} when there is no such account.
        guard let result = json["result"] as? [String: Any] else { return nil }
        return !(result["value"] is NSNull) && result["value"] != nil
    }
}
