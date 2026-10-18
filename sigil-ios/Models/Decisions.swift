import Foundation

/// What the engine returned for a transfer (SPEC §9.2).
enum Outcome: String, Sendable {
    case cleared, blocked, needsGuardian, needsProof
}

/// SPEC §9.4. Every code carries the words to show a person, because the agent
/// has to explain each outcome in plain language rather than quote the code.
enum ReasonCode: String, CaseIterable, Sendable {
    case frozen
    case policyInactive
    case policySignatureInvalid
    case recipientNotRegistered
    case duplicateRequest
    case invalidAmount
    case blockedCategory
    case rateLimitDay
    case overMaxPerRequest
    case overWeeklyCap
    case insufficientDelegation
    case auditMissing
    case auditFlagged
    case auditorInvalidOutput
    case proofRequired
    case signerFailed
    case signerRejected

    /// The wire form, so a screen can show what the backend actually sent.
    var code: String {
        switch self {
        case .frozen: "FROZEN"
        case .policyInactive: "POLICY_INACTIVE"
        case .policySignatureInvalid: "POLICY_SIGNATURE_INVALID"
        case .recipientNotRegistered: "RECIPIENT_NOT_REGISTERED"
        case .duplicateRequest: "DUPLICATE_REQUEST"
        case .invalidAmount: "INVALID_AMOUNT"
        case .blockedCategory: "BLOCKED_CATEGORY"
        case .rateLimitDay: "RATE_LIMIT_DAY"
        case .overMaxPerRequest: "OVER_MAX_PER_REQUEST"
        case .overWeeklyCap: "OVER_WEEKLY_CAP"
        case .insufficientDelegation: "INSUFFICIENT_DELEGATION"
        case .auditMissing: "AUDIT_MISSING"
        case .auditFlagged: "AUDIT_FLAGGED"
        case .auditorInvalidOutput: "AUDITOR_INVALID_OUTPUT"
        case .proofRequired: "PROOF_REQUIRED"
        case .signerFailed: "SIGNER_FAILED"
        case .signerRejected: "SIGNER_REJECTED"
        }
    }

    var explanation: String {
        switch self {
        case .frozen: "Everything is frozen until your guardian lifts it."
        case .policyInactive: "There's no signed policy in place yet."
        case .policySignatureInvalid: "The policy couldn't be verified, so nothing can be sent."
        case .recipientNotRegistered: "Your wallet hasn't been registered by your guardian."
        case .duplicateRequest: "This is the same request again, so it was only counted once."
        case .invalidAmount: "That amount isn't a valid one to send."
        case .blockedCategory: "That category is blocked in your policy."
        case .rateLimitDay: "You've used all your requests for today."
        case .overMaxPerRequest: "It's over the most that can go out in one request."
        case .overWeeklyCap: "It doesn't fit in what's left of this week."
        case .insufficientDelegation: "The reservoir doesn't have enough left in it."
        case .auditMissing: "The second check hasn't run yet."
        case .auditFlagged: "The Auditor flagged it, so your guardian decides."
        case .auditorInvalidOutput: "The second check couldn't be completed, so it was held."
        case .proofRequired: "A receipt is needed before this one goes out."
        case .signerFailed: "The transfer didn't go through on the network."
        case .signerRejected: "The signer refused it, so nothing was sent."
        }
    }
}

/// What a request looks like to a person. Wider than `Outcome` because the agent
/// can settle a request on its own — partially or by declining — without the
/// engine ever seeing it (System Architecture, "Decision outcomes").
enum RequestStatus: String, Hashable, Sendable {
    /// Full amount cleared and signed.
    case sent
    /// The agent offered less than was asked for.
    case partlySent
    /// Waiting on a receipt before it can go further.
    case needsProof
    /// Waiting on the guardian's signed answer.
    case needsGuardian
    /// The agent said no. No transfer was ever attempted.
    case declined
    /// An outer limit stopped it: the engine or the signer refused.
    case blocked

    var label: String {
        switch self {
        case .sent: "Sent"
        case .partlySent: "Part sent"
        case .needsProof: "Needs receipt"
        case .needsGuardian: "Needs guardian"
        case .declined: "Declined"
        case .blocked: "Blocked"
        }
    }

    /// Shorter wording for the dependent, who is talking to their own guardian.
    func label(guardianName: String) -> String {
        self == .needsGuardian ? "With \(guardianName)" : label
    }
}

enum RiskSignal: String, Sendable {
    case manipulation, purposeMismatch, pattern, proofMismatch, emergencyClaim, other

    var label: String {
        switch self {
        case .manipulation: "Manipulation"
        case .purposeMismatch: "Purpose mismatch"
        case .pattern: "Unusual pattern"
        case .proofMismatch: "Proof mismatch"
        case .emergencyClaim: "Emergency claim"
        case .other: "Other"
        }
    }
}

/// The checker's verdict (SPEC §8.3). It can only agree or flag — never approve,
/// never raise an amount.
struct AuditorVerdict: Sendable {
    enum Verdict: String, Sendable {
        case agree, flag

        var label: String {
            switch self {
            case .agree: "Auditor agreed"
            case .flag: "Auditor flagged"
            }
        }
    }

    let verdict: Verdict
    let reason: String
    let riskSignals: [RiskSignal]
}

/// What the agent suggests the guardian do, attached to every question it asks.
enum Recommendation: String, Sendable {
    case approve, deny, partial

    var label: String {
        switch self {
        case .approve: "Agent recommends approving"
        case .deny: "Agent recommends declining"
        case .partial: "Agent recommends a smaller amount"
        }
    }
}
