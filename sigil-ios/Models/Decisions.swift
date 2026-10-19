import Foundation

/// The agent's move on a request (`DecisionView.outcome`).
///
/// This is the agent layer's list, not SPEC §9.2's four engine outcomes: the agent
/// settles most requests itself, and only some of these ever reach the engine. The
/// gateway says new outcomes may appear, so anything unrecognised becomes `.unknown`
/// and is shown neutrally rather than dropped.
enum Outcome: String, CaseIterable, Sendable {
    case sentFull = "sent_full"
    case sentPartial = "sent_partial"
    case counterOffer = "counter_offer"
    case askedProof = "asked_proof"
    case askedGuardian = "asked_guardian"
    case askedDependent = "asked_dependent"
    case declined
    case outOfScope = "out_of_scope"
    // Set by code, never chosen by the model:
    case auditorFlagged = "auditor_flagged"
    case blocked
    case safeFallback = "safe_fallback"
    case transferPending = "transfer_pending"
    // A receipt check, not a request: the gateway settled an owed receipt with the proof
    // that was sent, or refused it. No money moves either way.
    case receiptAccepted = "receipt_accepted"
    case receiptRejected = "receipt_rejected"
    /// Never sent by the gateway: the app has no decision for the request yet, because the
    /// agent is still on it or its detail didn't load. Nothing is known to be moving.
    case awaitingDecision = "__awaiting_decision"
    case unknown = "__unknown"

    init(apiValue: String) {
        self = Outcome(rawValue: apiValue) ?? .unknown
    }

    var label: String {
        switch self {
        case .sentFull: "Sent"
        case .sentPartial: "Part sent"
        case .counterOffer: "Offered less"
        case .askedProof: "Needs proof"
        case .askedGuardian: "Needs guardian"
        case .askedDependent: "Agent asked back"
        case .declined: "Declined"
        case .outOfScope: "Not about money"
        case .auditorFlagged: "Auditor flagged"
        case .blocked: "Blocked"
        case .safeFallback: "Held back"
        case .transferPending: "On its way"
        case .receiptAccepted: "Receipt accepted"
        case .receiptRejected: "Receipt not accepted"
        case .awaitingDecision: "Being looked at"
        case .unknown: "Updated"
        }
    }

    /// Shorter wording for the dependent, who is talking to their own guardian.
    func label(guardianName: String) -> String {
        switch self {
        case .askedGuardian, .auditorFlagged: "Waiting for \(guardianName)"
        default: label
        }
    }

    /// `transfer_pending` means the money is already on its way: the gateway is
    /// explicit that it must never be shown with a retry button.
    var isMoneyMoving: Bool {
        self == .sentFull || self == .sentPartial || self == .transferPending
    }

    var needsGuardian: Bool {
        self == .askedGuardian || self == .auditorFlagged
    }

    var isStopped: Bool {
        self == .declined || self == .blocked || self == .outOfScope || self == .safeFallback
    }

    /// The gateway's answer to a receipt sent for money already paid out. It settles an
    /// obligation or refuses the proof; it never moves money and never asks the guardian.
    var isReceiptCheck: Bool {
        self == .receiptAccepted || self == .receiptRejected
    }
}

/// What the agent did, as the app is given it (`DecisionView`).
struct Decision: Sendable {
    let outcome: Outcome
    /// The agent's own words. The gateway says to show this to the dependent rather
    /// than compose our own explanation.
    let replyToDependent: String
    /// The source of truth for money actually moved.
    let amountSent: Units
    let transferID: String?
    /// Guardians only — never rendered on a dependent's screen.
    let summaryForGuardian: String?

    init(
        outcome: Outcome,
        replyToDependent: String,
        amountSent: Units = .zero,
        transferID: String? = nil,
        summaryForGuardian: String? = nil
    ) {
        self.outcome = outcome
        self.replyToDependent = replyToDependent
        self.amountSent = amountSent
        self.transferID = transferID
        self.summaryForGuardian = summaryForGuardian
    }
}

/// `TransferView.status`.
enum TransferStatus: String, Sendable {
    case blocked, pending, sent, failed

    var label: String {
        switch self {
        case .blocked: "Blocked"
        case .pending: "On its way"
        case .sent: "Sent"
        case .failed: "Failed"
        }
    }
}

enum TransferTrigger: String, Sendable {
    case request, allowance
}

/// One money event (`TransferView`).
struct Transfer: Identifiable, Sendable {
    let id: String
    let requestID: String?
    let trigger: TransferTrigger
    let amount: Units
    let category: Category
    let purpose: String
    let status: TransferStatus
    /// Free text from the engine or signer when something stopped it.
    let reason: String?
    let txSignature: String?
}

/// Who said what in a request's thread (`ThreadEntry`).
enum ThreadRole: String, Sendable {
    case dependent, agent
    case guardianAnswer = "guardian_answer"
    case systemEvent = "system_event"
}

struct ThreadEntry: Identifiable, Sendable {
    let id = UUID()
    let role: ThreadRole
    let text: String
    let at: String
}

/// Integrity flags the gateway sets on a proof at upload. They only make the agent
/// more careful — none of them blocks anything on their own.
enum ProofFlag: String, CaseIterable, Sendable {
    case duplicate
    case nearDuplicate = "near_duplicate"
    case noCameraMetadata = "no_camera_metadata"
    case screenshot
    case oldCapture = "old_capture"
    case edited
    case cameraSigned = "camera_signed"
    /// A PDF receipt whose shop signature the gateway verified. Without this a PDF counts
    /// for nothing, so it is the one flag that makes a document evidence.
    case issuerSigned = "issuer_signed"
    /// A PDF whose signature did not verify: stored, never shown to the agent, settles
    /// nothing.
    case uncheckedDocument = "unchecked_document"
    case aiGenerated = "ai_generated"
    case aiSuspected = "ai_suspected"
    case rephotographedScreen = "rephotographed_screen"
    /// A flag this version doesn't know. The gateway may add more, and something flagged
    /// should never read as unflagged.
    case unknown = "__unknown"

    init(apiValue: String) {
        self = ProofFlag(rawValue: apiValue) ?? .unknown
    }

    var label: String {
        switch self {
        case .duplicate: "Same file as an earlier receipt"
        case .nearDuplicate: "Nearly the same picture as before"
        case .noCameraMetadata: "No camera information"
        case .screenshot: "Looks like a screenshot"
        case .oldCapture: "Taken over 30 days ago"
        case .edited: "Edited after it was taken"
        case .cameraSigned: "Taken in the app"
        case .issuerSigned: "Signed by the shop"
        case .uncheckedDocument: "Not signed by the shop"
        case .aiGenerated: "Made by AI"
        case .aiSuspected: "Might be made by AI"
        case .rephotographedScreen: "A photo of a screen"
        case .unknown: "Flagged by the checks"
        }
    }

    /// Only a verified capture or a shop-signed PDF is reassuring; the rest are cautions.
    var isReassuring: Bool { self == .cameraSigned || self == .issuerSigned }
}

enum ProofKind: String, Sendable {
    case receipt, quote, photo
}

/// How a receipt reaches the gateway. There is no gallery picker and screenshots are not
/// accepted, so an online order is shown by the PDF the shop sent.
enum ProofSource: String, Sendable, CaseIterable, Identifiable {
    case camera
    case document

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Take a photo"
        case .document: "Upload the PDF"
        }
    }

    var detail: String {
        switch self {
        case .camera: "For a paper receipt, in the app's own camera"
        case .document: "For an online order, the PDF the shop emailed you"
        }
    }

    var icon: String {
        switch self {
        case .camera: "camera.fill"
        case .document: "doc.text.fill"
        }
    }
}

struct Proof: Identifiable, Sendable {
    let id: String
    let kind: ProofKind
    /// `"photo"` only for a verified in-app capture; a plain upload is `"file"`.
    let source: String
    let flags: [ProofFlag]
    let capturedAt: String?
    let uploadedAt: String

    var isVerifiedCapture: Bool { source == "photo" }
}

/// What the agent suggests the guardian do (`QuestionView.recommendation`).
enum Recommendation: String, Sendable {
    case approve, deny, partial

    init(apiValue: String) {
        self = Recommendation(rawValue: apiValue) ?? .deny
    }

    var label: String {
        switch self {
        case .approve: "Agent recommends approving"
        case .deny: "Agent recommends declining"
        case .partial: "Agent recommends a smaller amount"
        }
    }
}

enum Urgency: String, Sendable {
    case low, normal, high

    init(apiValue: String) {
        self = Urgency(rawValue: apiValue) ?? .normal
    }
}
