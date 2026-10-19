import Foundation

/// What the gateway sends back, decoded with `convertFromSnakeCase`.
///
/// These mirror the App API's schemas exactly and are kept separate from the types the
/// screens use: a response shape is the gateway's to change, a screen's model is ours.

struct NonceResponse: Decodable {
    let nonce: String
    /// The exact text to sign. Only set for `purpose: "login"`; for the others the app
    /// builds the text itself from the templates in the README.
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
    let dependentId: String
    let dependentWallet: String
    let dependentName: String?
    let dependentTokenAccount: String
    let guardianTokenAccount: String
    let timezone: String
    let frozen: Bool
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

struct ProcessedRequestDTO: Decodable {
    let request: RequestDTO
    let decision: DecisionDTO
}

struct ProofObligationDTO: Decodable {
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
    let createdAt: String
}

struct NotificationDTO: Decodable {
    let id: String
    /// Null when it is about the guardian as a whole, such as the shared reservoir.
    let familyId: String?
    let message: String
    let createdAt: String
    let readAt: String?
}

struct RegisteredFamilyDTO: Decodable {
    let family: FamilyDTO
    /// A fresh token; the old one still works, since tokens carry no family.
    let token: String
}

struct AnsweredDTO: Decodable {
    let question: QuestionDTO
    /// The agent's next move, when it could run.
    let decision: DecisionDTO?
}

struct FreezeDTO: Decodable {
    let frozen: Bool
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

// MARK: Policy interview

struct ChecklistItemDTO: Decodable, Identifiable {
    let name: String
    let label: String
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

struct DraftViewDTO: Decodable {
    let id: String
    let version: Int
    let body: PolicyBodyDTO
    let bodyHash: String
    let testScenarios: [String]
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

struct ActivatedPolicyDTO: Decodable {
    let id: String
    let version: Int
}
