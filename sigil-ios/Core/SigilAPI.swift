import Foundation

/// The gateway's App API.
///
/// Every route except `/auth/*` carries the session token. A guardian with more than one
/// dependent names the family in `X-Family-Id`; without it the gateway answers
/// `400 FAMILY_REQUIRED`.
struct SigilAPI {
    var baseURL = URL(string: "https://api.iden.casa")!
    var token: String?
    /// The family guardian calls are about, when there is more than one dependent.
    var familyID: String?

    /// Agent-backed calls block while the agent runs, which the gateway caps at 150 s.
    static let agentTimeout: TimeInterval = 200
    static let timeout: TimeInterval = 30

    // MARK: Sign-in

    func nonce(wallet: String, purpose: String) async throws -> NonceResponse {
        try await send(
            "auth/nonce", method: "POST", body: ["wallet": wallet, "purpose": purpose],
            authorized: false
        )
    }

    func verify(wallet: String, message: String, signature: String) async throws -> Session {
        try await send(
            "auth/verify", method: "POST",
            body: ["wallet": wallet, "message": message, "signature_b58": signature],
            authorized: false
        )
    }

    func me() async throws -> Me {
        try await send("me")
    }

    // MARK: Reading

    func families() async throws -> [FamilyDTO] {
        try await send("families")
    }

    func budget() async throws -> BudgetDTO {
        try await send("budget")
    }

    func activePolicy() async throws -> ActivePolicyDTO {
        try await send("policy/active")
    }

    func requests() async throws -> [RequestDTO] {
        try await send("requests")
    }

    func proofObligations() async throws -> [ProofObligationDTO] {
        try await send("proof-obligations")
    }

    func questions(status: String = "open") async throws -> [QuestionDTO] {
        try await send("questions?status=\(status)")
    }

    func notifications() async throws -> [NotificationDTO] {
        try await send("notifications")
    }

    // MARK: Asking

    func createRequest(
        message: String, amount: Units?, emergency: Bool
    ) async throws -> ProcessedRequestDTO {
        var body: [String: Any] = ["message": message, "emergency_claimed": emergency]
        if let amount { body["amount_requested"] = amount.raw }
        return try await send("requests", method: "POST", body: body, timeout: Self.agentTimeout)
    }

    // MARK: Plumbing

    private func send<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        authorized: Bool = true,
        timeout: TimeInterval = SigilAPI.timeout
    ) async throws -> Response {
        var request = URLRequest(
            url: baseURL.appending(path: "api/v1").appending(path: path),
            timeoutInterval: timeout
        )
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let familyID {
            request.setValue(familyID, forHTTPHeaderField: "X-Family-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, data: data)
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.undecodable(String(describing: error))
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

/// `{"error": {"code": "UPPER_SNAKE", "message": "..."}}`, plus the cases that never reach
/// the server.
enum APIError: Error, Equatable {
    /// A code the app reacts to, with the gateway's own message.
    case server(code: String, message: String, status: Int)
    case offline
    case undecodable(String)

    init(status: Int, data: Data) {
        struct Envelope: Decodable {
            struct Inner: Decodable {
                let code: String
                let message: String
            }
            let error: Inner
        }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            self = .server(
                code: envelope.error.code, message: envelope.error.message, status: status
            )
        } else {
            self = .server(code: "UNEXPECTED", message: "Something went wrong.", status: status)
        }
    }

    var code: String? {
        if case .server(let code, _, _) = self { return code }
        return nil
    }

    /// What to put on screen. The gateway's messages are written for people.
    var readable: String {
        switch self {
        case .server(let code, let message, _):
            switch code {
            case "PROOF_OUTSTANDING": "Send the receipt for the money you already got first."
            case "DAILY_LIMIT_REACHED": "You've asked as often as you can today. Try tomorrow."
            case "RATE_LIMITED": "That was a lot at once — wait a moment and try again."
            case "AGENT_UNAVAILABLE": "The agent is busy. Try again in a moment."
            case "FAMILY_REQUIRED": "Choose which dependent this is about."
            default: message
            }
        case .offline: "You seem to be offline."
        case .undecodable: "The app couldn't read the answer from the server."
        }
    }

    /// `401` means the session is gone: the gateway has no refresh token, so sign in again.
    var needsSignIn: Bool {
        if case .server(_, _, let status) = self { return status == 401 }
        return false
    }
}
