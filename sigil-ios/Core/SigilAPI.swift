import Foundation

/// The gateway's App API.
///
/// Every route except `/auth/*` carries the session token. A guardian with more than one
/// dependent names the family in `X-Family-Id`; without it the gateway answers
/// `400 FAMILY_REQUIRED`.
struct SigilAPI {
    /// The gateway. The deployment also runs the agent layer, so no local stack is needed.
    var baseURL = URL(string: "https://api.iden.casa")!

    /// The domain the gateway writes into its sign-in text ("iden.casa wants you to sign
    /// in…"). A real wallet compares this with the `app_url` it is given, so the two must
    /// agree when one arrives.
    static let signInDomain = "iden.casa"

    var token: String?
    /// The family guardian calls are about, when there is more than one dependent.
    var familyID: String?

    /// Agent-backed calls block while the agent runs, which the gateway caps at 150 s.
    nonisolated static let agentTimeout: TimeInterval = 200
    nonisolated static let timeout: TimeInterval = 30

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

    // MARK: Families

    func families() async throws -> [FamilyDTO] {
        try await send("families")
    }

    func family() async throws -> FamilyDTO {
        try await send("family")
    }

    func registerFamily(
        dependentWallet: String,
        dependentTokenAccount: String,
        guardianTokenAccount: String,
        dependentName: String?,
        nonce: String,
        signature: String
    ) async throws -> RegisteredFamilyDTO {
        var body: [String: Any] = [
            "dependent_wallet": dependentWallet,
            "dependent_token_account": dependentTokenAccount,
            "guardian_token_account": guardianTokenAccount,
            "nonce": nonce,
            "registration_signature_b58": signature,
        ]
        if let dependentName, !dependentName.isEmpty { body["dependent_name"] = dependentName }
        return try await send("families", method: "POST", body: body)
    }

    // MARK: Reading

    func budget() async throws -> BudgetDTO {
        try await send("budget")
    }

    func activePolicy() async throws -> ActivePolicyDTO {
        try await send("policy/active")
    }

    func proposals() async throws -> [ProposalDTO] {
        try await send("policy/proposals")
    }

    func requests() async throws -> [RequestDTO] {
        try await send("requests")
    }

    func request(id: String) async throws -> RequestDetailDTO {
        try await send("requests/\(id)")
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

    func markRead(notification id: String) async throws {
        _ = try await sendDiscardingResult("notifications/\(id)/read", method: "POST")
    }

    func history() async throws -> HistoryDTO {
        try await send("history")
    }

    func audit() async throws -> AuditTrailDTO {
        try await send("audit")
    }

    // MARK: Asking

    func createRequest(
        message: String, amount: Units?, emergency: Bool
    ) async throws -> ProcessedRequestDTO {
        var body: [String: Any] = ["message": message, "emergency_claimed": emergency]
        if let amount { body["amount_requested"] = amount.raw }
        return try await send("requests", method: "POST", body: body, timeout: Self.agentTimeout)
    }

    func addMessage(
        to requestID: String, message: String, amount: Units? = nil
    ) async throws -> ProcessedRequestDTO {
        var body: [String: Any] = ["message": message]
        if let amount { body["amount_requested"] = amount.raw }
        return try await send(
            "requests/\(requestID)/messages", method: "POST", body: body,
            timeout: Self.agentTimeout
        )
    }

    /// Retried after `AGENT_UNAVAILABLE`: the request is already stored, only the agent run
    /// failed.
    func process(requestID: String) async throws -> ProcessedRequestDTO {
        try await send(
            "requests/\(requestID)/process", method: "POST", timeout: Self.agentTimeout
        )
    }

    // MARK: Proofs

    /// Uploads a receipt. `captureClaim` and `captureSignature` are set only for a verified
    /// in-app capture; without them the gateway stores it as a plain file.
    func uploadProof(
        requestID: String,
        data: Data,
        filename: String,
        mediaType: String,
        kind: String,
        captureClaim: String? = nil,
        captureSignature: String? = nil
    ) async throws -> UploadedProofDTO {
        var fields: [String: String] = ["kind": kind]
        if let captureClaim { fields["capture_claim"] = captureClaim }
        if let captureSignature { fields["capture_signature"] = captureSignature }
        return try await upload(
            "requests/\(requestID)/proofs",
            fields: fields,
            data: data,
            filename: filename,
            mediaType: mediaType
        )
    }

    // MARK: Verified capture

    func captureChallenge() async throws -> ChallengeDTO {
        try await send("capture/challenge", method: "POST")
    }

    func enrolDevice(
        challenge: String, keyID: String, attestation: String
    ) async throws -> DeviceDTO {
        try await send(
            "capture/devices", method: "POST",
            body: ["challenge": challenge, "key_id": keyID, "attestation_object": attestation]
        )
    }

    func devices() async throws -> [DeviceDTO] {
        try await send("capture/devices")
    }

    func captureTicket(requestID: String, deviceID: String) async throws -> TicketDTO {
        try await send(
            "requests/\(requestID)/capture-tickets", method: "POST",
            body: ["device_id": deviceID]
        )
    }

    // MARK: Signed guardian actions

    func answerQuestion(
        id: String, approve: Bool, amount: Units?, note: String?, nonce: String, signature: String
    ) async throws -> AnsweredDTO {
        var body: [String: Any] = [
            "decision": approve ? "approve" : "deny",
            "nonce": nonce,
            "signature_b58": signature,
        ]
        // An approval needs an amount; a denial must not carry one.
        if approve, let amount { body["amount_units"] = amount.raw }
        if let note, !note.isEmpty { body["note"] = note }
        return try await send(
            "questions/\(id)/answer", method: "POST", body: body, timeout: Self.agentTimeout
        )
    }

    func freeze(frozen: Bool, nonce: String, signature: String) async throws -> FreezeDTO {
        try await send(
            "freeze", method: "POST",
            body: ["frozen": frozen, "nonce": nonce, "signature_b58": signature]
        )
    }

    // MARK: Policy interview

    /// No message starts the interview; each later call sends the guardian's own words.
    /// The agent runs on every turn, so this needs the long timeout.
    func interview(message: String? = nil) async throws -> InterviewDTO {
        try await send(
            "policy/interview", method: "POST",
            body: message.map { ["message": $0] } ?? [:], timeout: Self.agentTimeout
        )
    }

    /// The interview already in progress, if there is one. Sending no message is only
    /// valid for a brand-new interview, so this is what says which case we are in.
    func interviewTranscript() async throws -> TranscriptDTO {
        try await send("policy/interview")
    }

    func abandonInterview() async throws {
        _ = try await sendDiscardingResult("policy/interview", method: "DELETE")
    }

    func draft(id: String) async throws -> DraftViewDTO {
        try await send("policy/drafts/\(id)")
    }

    func activateDraft(
        id: String, nonce: String, signature: String
    ) async throws -> ActivatedPolicyDTO {
        try await send(
            "policy/drafts/\(id)/activate", method: "POST",
            body: ["nonce": nonce, "signature_b58": signature]
        )
    }

    // MARK: Live events

    /// The SSE stream for the selected family. Each event carries ids only, so the app
    /// refetches through the endpoints above.
    func eventStream() -> URLRequest {
        var request = URLRequest(
            url: baseURL.appending(path: "api/v1").appending(path: "events"),
            timeoutInterval: .infinity
        )
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Never in the URL: the token would end up in logs and proxies.
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let familyID { request.setValue(familyID, forHTTPHeaderField: "X-Family-Id") }
        return request
    }

    // MARK: Plumbing

    private func request(
        _ path: String, method: String, authorized: Bool, timeout: TimeInterval
    ) -> URLRequest {
        var request = URLRequest(
            url: baseURL.appending(path: "api/v1").appending(path: path),
            timeoutInterval: timeout
        )
        request.httpMethod = method
        if authorized, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let familyID {
            request.setValue(familyID, forHTTPHeaderField: "X-Family-Id")
        }
        return request
    }

    private func send<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        authorized: Bool = true,
        timeout: TimeInterval = SigilAPI.timeout
    ) async throws -> Response {
        var request = request(path, method: method, authorized: authorized, timeout: timeout)
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data = try await perform(request)
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.undecodable(String(describing: error))
        }
    }

    @discardableResult
    private func sendDiscardingResult(
        _ path: String, method: String, timeout: TimeInterval = SigilAPI.timeout
    ) async throws -> Data {
        try await perform(request(path, method: method, authorized: true, timeout: timeout))
    }

    private func upload<Response: Decodable>(
        _ path: String,
        fields: [String: String],
        data: Data,
        filename: String,
        mediaType: String
    ) async throws -> Response {
        let boundary = "sigil-\(UUID().uuidString)"
        var request = request(path, method: "POST", authorized: true, timeout: Self.agentTimeout)
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )

        var payload = Data()
        func append(_ string: String) { payload.append(Data(string.utf8)) }
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mediaType)\r\n\r\n")
        payload.append(data)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = payload

        let result = try await perform(request)
        do {
            return try Self.decoder.decode(Response.self, from: result)
        } catch {
            throw APIError.undecodable(String(describing: error))
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw APIError.timedOut
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, data: data)
        }
        return data
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

/// `{"error": {"code": "UPPER_SNAKE", "message": "..."}}`, plus the failures that never
/// reach the gateway.
enum APIError: Error, Equatable {
    /// A code the app reacts to, with the gateway's own message.
    case server(code: String, message: String, status: Int)
    case offline
    case timedOut
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
            return
        }
        // The deployment sits behind a proxy that answers with an HTML page, not the
        // gateway's envelope, and cuts long agent runs short. Treat that as the agent
        // being unavailable, which is retryable, rather than as an unknown failure.
        if (502...504).contains(status) {
            self = .server(
                code: "AGENT_UNAVAILABLE",
                message: "The agent didn't answer in time.",
                status: status
            )
        } else {
            self = .server(code: "UNEXPECTED", message: "Something went wrong.", status: status)
        }
    }

    var code: String? {
        if case .server(let code, _, _) = self { return code }
        return nil
    }

    /// What to put on screen. The gateway's own messages are written for people.
    var readable: String {
        switch self {
        case .server(let code, let message, _):
            switch code {
            case "DAILY_LIMIT_REACHED": "You've asked as often as you can today. Try tomorrow."
            case "RATE_LIMITED": "That was a lot at once — wait a moment and try again."
            case "AGENT_UNAVAILABLE": "The agent is busy. Try again in a moment."
            case "FAMILY_REQUIRED": "Choose which dependent this is about."
            case "INTERVIEW_TOO_LONG": "This conversation got long. Start the policy over."
            case "ATTESTATION_FAILED": "This device couldn't be verified for in-app receipts."
            case "UNSUPPORTED_PROOF": "That file can't be used as a receipt."
            default: message
            }
        case .offline: "You seem to be offline."
        case .timedOut: "The agent is taking too long. Try again in a moment."
        case .undecodable: "The app couldn't read the answer from the server."
        }
    }

    /// Worth offering another go, as opposed to something the person must change.
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut: true
        case .server(let code, _, _): code == "AGENT_UNAVAILABLE" || code == "RATE_LIMITED"
        case .undecodable: false
        }
    }

    /// `401` means the session is gone: the gateway has no refresh token, so sign in again.
    var needsSignIn: Bool {
        if case .server(_, _, let status) = self { return status == 401 }
        return false
    }
}
