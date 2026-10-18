import SwiftUI

enum Role: String {
    case guardian, dependent
}

/// Signed-in state shared by the whole app.
@Observable
final class AppSession {
    var role: Role?

    /// The guardian's signed kill switch (SEC-17). While frozen the engine refuses
    /// every transfer, so the whole app reads this one flag.
    var frozen = false

    func signIn(as role: Role) {
        withAnimation(.easeInOut(duration: 0.3)) { self.role = role }
    }

    func signOut() {
        withAnimation(.easeInOut(duration: 0.3)) { role = nil }
    }
}

struct Guardian: Sendable {
    let name: String
    /// What the dependents call them, used in dependent-facing copy.
    let shortName: String
    let initials: String
    let wallet: String
}

struct Dependent: Identifiable, Sendable {
    let id: String
    let name: String
    let initials: String
    /// The one address their allowance can reach, registered by guardian
    /// signature (SPEC §8.4).
    let tokenAccount: String
    let avatarBackground: Color
    let avatarForeground: Color
    let sentThisMonth: Units
    let requestsThisMonth: Int
    let awaitingGuardian: Int
}

/// `GET /budget`. A budget week runs Monday to Monday in the family's timezone.
struct Budget: Sendable {
    let spent: Units
    /// Cleared and reserved, but not yet confirmed on chain.
    let reserved: Units
    let weeklyCap: Units
    let remaining: Units
    /// `null` when the crypto layer cannot be read — the app must show that it is
    /// unknown rather than invent a number.
    let delegatedRemaining: Units?
    let resetText: String

    var fraction: Double { (spent + reserved).fraction(of: weeklyCap) }
}

/// One request as a list row. Built from the request plus its latest decision.
struct ActivityItem: Identifiable, Sendable {
    let id = UUID()
    let outcome: Outcome
    let title: String
    let dependentID: String
    /// What was asked for.
    let amount: Units
    /// What actually moved, from `decision.amount_sent`.
    let amountSent: Units
    let category: Category
    /// `decision.reply_to_dependent` — the agent's own words.
    let reply: String
    /// `decision.summary_for_guardian`, which dependents must never see.
    let summaryForGuardian: String?
    let emergencyClaimed: Bool
    let txSignature: String?
    let time: String

    init(
        outcome: Outcome,
        title: String,
        dependentID: String,
        amount: Units,
        amountSent: Units = .zero,
        category: Category,
        reply: String,
        summaryForGuardian: String? = nil,
        emergencyClaimed: Bool = false,
        time: String,
        txSignature: String? = nil
    ) {
        self.outcome = outcome
        self.title = title
        self.dependentID = dependentID
        self.amount = amount
        self.amountSent = amountSent
        self.category = category
        self.reply = reply
        self.summaryForGuardian = summaryForGuardian
        self.emergencyClaimed = emergencyClaimed
        self.txSignature = txSignature
        self.time = time
    }
}

struct ActivityGroup: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let items: [ActivityItem]
}

/// `QuestionView`. Answering takes a wallet signature; a claim in chat never counts.
struct GuardianQuestion: Identifiable, Sendable {
    let id: String
    let requestID: String?
    let dependentID: String
    let title: String
    let question: String
    let amount: Units
    let category: Category
    let recommendation: Recommendation
    let recommendedAmount: Units?
    let urgency: Urgency
    /// The maker's case.
    let agentView: String
    /// The checker's case. Absent when no review was required.
    let auditorView: String?
    let askedAgo: String
    let emergencyClaimed: Bool
    let proofs: [Proof]
}

struct Notification: Identifiable, Sendable {
    let id: String
    let message: String
    let time: String
    let isRead: Bool
}

struct WeeklySummary: Identifiable, Sendable {
    let id: String
    let weekOf: String
    let body: String
    let sent: Units
    let requests: Int
    let flagged: Int
}

/// One link in the append-only, hash-chained log. The gateway re-verifies the whole
/// chain on every read and returns `chain_valid` with it.
struct AuditLogEntry: Identifiable, Sendable {
    let id: Int
    let event: String
    let detail: String
    let time: String
    let hashPrefix: String
}
