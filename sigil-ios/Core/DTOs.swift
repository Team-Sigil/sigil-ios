import Foundation

/// What the gateway sends back, decoded with `convertFromSnakeCase`.
///
/// These mirror the App API's schemas (gateway README, "App API") and stay separate from
/// the types the screens use: a response shape is the gateway's to change, a screen's
/// model is ours. Dates arrive as ISO 8601 strings and are parsed by `Dates`.

struct NonceResponse: Decodable {
    let nonce: String
    /// The exact text to sign. Only set for `purpose: "login"`; for the others the app
    /// builds the text itself (see `SignedMessage`).
    let message: String?
    let expiresAt: String
}

struct Session: Decodable {
    let token: String
    let role: String
    /// Set only when the guardian has exactly one dependent.
    let familyId: String?
    let familyIds: [String]
}

struct Me: Decodable {
    let userId: String
    let wallet: String
    let role: String
    let familyId: String?
    let familyIds: [String]
    let displayName: String?
    let locale: String?
}

struct FamilyDTO: Decodable {
    let id: String
    let guardianId: String
    let guardianWallet: String
    let dependentId: String
    let dependentWallet: String
    let dependentName: String?
    let dependentTokenAccount: String
    let guardianTokenAccount: String
    let timezone: String
    let frozen: Bool
    let createdAt: String
}

struct RegisteredFamilyDTO: Decodable {
    let family: FamilyDTO
    /// A fresh token; the old one still works, since tokens carry no family.
    let token: String
}

struct BudgetDTO: Decodable {
    let weekStart: String
    let spent: Int64
    let reserved: Int64
    let weeklyCap: Int64
    let remaining: Int64
    /// Null when the crypto layer cannot be read; the app must say so, not invent a figure.
    let delegatedRemaining: Int64?
}

struct PolicyBodyDTO: Decodable {
    let weeklyCap: Int64
    let maxPerRequest: Int64
    let blockedCategories: [String]
    let proofThreshold: Int64
    let reviewThreshold: Int64?
    let allowance: AllowanceDTO?
    /// Guardians only: the gateway omits it for a dependent (SEC-10).
    let guidance: String?

    struct AllowanceDTO: Decodable {
        let amount: Int64
        let weekday: Int
    }
}

struct ActivePolicyDTO: Decodable {
    let id: String
    let version: Int
    let body: PolicyBodyDTO
    let bodyHash: String?
    let activatedAt: String?
}

struct DecisionDTO: Decodable {
    let outcome: String
    let replyToDependent: String
    let amountSent: Int64
    let transferId: String?
    /// Guardians only.
    let summaryForGuardian: String?
    let createdAt: String?
}

struct RequestDTO: Decodable {
    let id: String
    let message: String
    let amountRequested: Int64?
    let emergencyClaimed: Bool
    let alreadySent: Int64
    let createdAt: String
}

/// `GET /requests/{id}`: the request with everything said and done about it. The list
/// endpoint carries no decisions, so this is what the activity rows are built from.
struct RequestDetailDTO: Decodable {
    let id: String
    let message: String
    let amountRequested: Int64?
    let emergencyClaimed: Bool
    let alreadySent: Int64
    let createdAt: String
    let thread: [ThreadEntryDTO]
    let proofs: [ProofDTO]
    let decisions: [DecisionDTO]

    /// The latest decision is what the row shows.
    var decision: DecisionDTO? { decisions.last }
}

struct ThreadEntryDTO: Decodable {
    let role: String
    let text: String
    let at: String
}

struct ProofDTO: Decodable {
    let id: String
    let kind: String
    let mediaType: String
    let sizeBytes: Int
    /// `"photo"` only for a verified in-app capture; a plain upload is `"file"`.
    let source: String
    let flags: [String]
    let capturedAt: String?
    let uploadedAt: String
}

struct ProcessedRequestDTO: Decodable {
    let request: RequestDTO
    let decision: DecisionDTO
}

struct UploadedProofDTO: Decodable {
    let proof: ProofDTO
    let decision: DecisionDTO
}

struct ProofObligationDTO: Decodable, Identifiable {
    let id: String
    let requestId: String
    let transferId: String
    let amount: Int64
    let createdAt: String
}

struct QuestionDTO: Decodable {
    let id: String
    let requestId: String?
    let question: String
    let recommendation: String
    let recommendedAmount: Int64?
    let urgency: String
    let agentView: String
    /// Absent when no review was required.
    let auditorView: String?
    let status: String
    let decision: String?
    let approvedAmount: Int64?
    let note: String?
    let createdAt: String
    let answeredAt: String?
}

struct AnsweredDTO: Decodable {
    let question: QuestionDTO
    /// The agent's next move, when it could run.
    let decision: DecisionDTO?
}

struct FreezeDTO: Decodable {
    let frozen: Bool
}

struct NotificationDTO: Decodable {
    let id: String
    /// Null when it is about the guardian as a whole, such as the shared reservoir.
    let familyId: String?
    let message: String
    let createdAt: String
    let readAt: String?
}

struct TransferDTO: Decodable {
    let id: String
    let requestId: String?
    let trigger: String
    let amount: Int64
    let category: String
    let purpose: String
    let status: String
    let reason: String?
    let txSignature: String?
    let createdAt: String
}

struct HistoryItemDTO: Decodable {
    let at: String
    let kind: String
    let amount: Int64
    let category: String
    let purpose: String?
}

struct HistoryDTO: Decodable {
    let items: [HistoryItemDTO]
    let transfers: [TransferDTO]
}

struct AuditEntryDTO: Decodable {
    let id: Int
    let eventType: String
    let payload: [String: AnyCodable]
    let prevHash: String
    let hash: String
    let createdAt: String
}

struct AuditTrailDTO: Decodable {
    let entries: [AuditEntryDTO]
    /// Recomputed end to end on every read (SEC-16).
    let chainValid: Bool
}

struct ProposalDTO: Decodable, Identifiable {
    let id: String
    let change: String
    let evidence: String
    let createdAt: String
}

// MARK: Verified in-app capture (App Attest)

struct ChallengeDTO: Decodable {
    let challenge: String
    let expiresAt: String
}

struct DeviceDTO: Decodable, Identifiable {
    let id: String
    let keyId: String?
    let createdAt: String?
    let revokedAt: String?
}

struct TicketDTO: Decodable {
    let ticket: String
    let requestId: String
    let deviceId: String
    let expiresAt: String
}

// MARK: Policy interview

struct ChecklistItemDTO: Decodable, Identifiable {
    let name: String
    let label: String
    let kind: String?
    let required: Bool
    /// "missing", "set", … — what the agent has pinned down so far.
    let status: String
    let summary: String?

    var id: String { name }
    var done: Bool { status != "missing" }
}

struct InterviewProgressDTO: Decodable {
    let requiredTotal: Int
    let requiredDone: Int
}

/// One of the agent's "if X asks for Y, I would Z" scenarios. Two fields, not a sentence.
struct TestScenarioDTO: Decodable, Identifiable {
    let scenario: String
    let whatIWouldDo: String

    var id: String { scenario }
    /// How the screens show it, as one line.
    var sentence: String { "\(scenario) — \(whatIWouldDo)" }
}

struct DraftViewDTO: Decodable {
    let id: String
    let version: Int
    let body: PolicyBodyDTO
    let bodyHash: String
    let testScenarios: [TestScenarioDTO]
    let openQuestions: [String]?
}

struct InterviewDTO: Decodable {
    let interviewId: String
    /// `needs_input`, `ready`, or `unavailable` (nothing stored: send the same message again).
    let status: String
    let phase: String?
    let question: String?
    let questionKind: String?
    let checklist: [ChecklistItemDTO]
    let progress: InterviewProgressDTO?
    /// The exact draft to sign, once `ready`.
    let draft: DraftViewDTO?
    let turnsUsed: Int
    let maxTurns: Int
}

/// `GET /policy/interview`: the conversation so far, so a half-finished interview can be
/// picked up instead of started again.
struct TranscriptDTO: Decodable {
    let interviewId: String
    /// `open`, `completed` (its draft awaits a signature) or `abandoned`.
    let status: String
    let turns: [InterviewTurnDTO]
    let draftPolicyId: String?

    /// The question the guardian is being asked right now.
    var lastAgentTurn: InterviewTurnDTO? {
        turns.last { $0.role == "agent" }
    }
}

struct InterviewTurnDTO: Decodable, Identifiable {
    let role: String
    let text: String
    /// `question`, `confirmation` or `review`, on agent turns.
    let kind: String?
    let at: String

    var id: String { "\(role)-\(at)-\(text.prefix(12))" }
}

struct ActivatedPolicyDTO: Decodable {
    let id: String
    let version: Int
}

/// Just enough to carry the audit log's free-form payload without modelling every event.
struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let string = try? container.decode(String.self) { value = string }
        else if let array = try? container.decode([AnyCodable].self) { value = array.map(\.value) }
        else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else { value = "" }
    }

    var text: String {
        switch value {
        case let string as String: string
        case let int as Int: String(int)
        case let double as Double: String(double)
        case let bool as Bool: bool ? "true" : "false"
        default: ""
        }
    }
}

/// The gateway's timestamps, with or without fractional seconds.
///
/// Every formatter here pins the Gregorian calendar and a fixed locale. The team's devices
/// are set to Thailand, where the default calendar is Buddhist: without pinning, a
/// `DateFormatter` reads the gateway's "2026-10-19" as Buddhist year 2026 — 1483 CE — and
/// every date on screen is wrong by 543 years.
enum Dates {
    static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    /// A formatter for one fixed pattern, safe whatever the device's calendar is set to.
    static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = gregorian
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain = ISO8601DateFormatter()

    static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return withFraction.date(from: iso) ?? plain.date(from: iso)
    }

    /// "8 min", "2 h", "Yesterday" — the shape the rows already use.
    static func ago(_ iso: String?, now: Date = Date()) -> String {
        guard let date = parse(iso) else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) h" }
        let days = Int(seconds / 86_400)
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days) d" }
        return short(iso)
    }

    /// "2 Oct"
    static func short(_ iso: String?) -> String {
        guard let date = parse(iso) else { return "" }
        return formatter("d MMM").string(from: date)
    }

    /// "1:20 pm", for a time on the same day.
    static func clock(_ iso: String?) -> String {
        guard let date = parse(iso) else { return "" }
        return formatter("h:mm a").string(from: date).lowercased()
    }

    /// The day heading the activity list groups by: "Today", "Yesterday", "Tue 14 Oct".
    static func dayLabel(_ date: Date, now: Date = Date()) -> String {
        if gregorian.isDateInToday(date) { return "Today" }
        if gregorian.isDateInYesterday(date) { return "Yesterday" }
        return formatter("E d MMM").string(from: date)
    }

    /// "MON 19 OCT", the date line at the top of the guardian's home.
    static func today(_ now: Date = Date()) -> String {
        formatter("E d MMM").string(from: now).uppercased()
    }

    /// The first day of the month `now` falls in, for "sent this month".
    static func monthStart(_ now: Date = Date()) -> Date {
        gregorian.dateInterval(of: .month, for: now)?.start ?? .distantPast
    }
}
