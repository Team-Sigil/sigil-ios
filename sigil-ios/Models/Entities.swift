import SwiftUI

enum Role {
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

/// A budget week: Monday 00:00 to Monday 00:00 in the family's timezone (SPEC §6.2).
struct Budget: Sendable {
    let spent: Units
    /// Cleared but not yet confirmed on-chain, so it is already committed.
    let reserved: Units
    let weeklyCap: Units
    /// What is left of the guardian's on-chain delegation, read from the chain.
    let delegatedRemaining: Units
    let resetText: String

    var remaining: Units { weeklyCap - spent - reserved }
    var fraction: Double { (spent + reserved).fraction(of: weeklyCap) }
}

/// One decision, as it appears in a history or activity list.
struct ActivityItem: Identifiable, Sendable {
    let id = UUID()
    let status: RequestStatus
    let title: String
    let dependentID: String
    let amount: Units
    /// Set when the agent sent less than was asked for.
    let sentAmount: Units?
    let category: Category
    /// The plain-language explanation shown to people.
    let note: String
    let reasonCodes: [ReasonCode]
    let verdict: AuditorVerdict?
    let time: String
    let txSignature: String?

    init(
        status: RequestStatus,
        title: String,
        dependentID: String,
        amount: Units,
        sentAmount: Units? = nil,
        category: Category,
        note: String,
        reasonCodes: [ReasonCode] = [],
        verdict: AuditorVerdict? = nil,
        time: String,
        txSignature: String? = nil
    ) {
        self.status = status
        self.title = title
        self.dependentID = dependentID
        self.amount = amount
        self.sentAmount = sentAmount
        self.category = category
        self.note = note
        self.reasonCodes = reasonCodes
        self.verdict = verdict
        self.time = time
        self.txSignature = txSignature
    }
}

struct ActivityGroup: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let items: [ActivityItem]
}

/// Something the agent has asked the guardian to settle. Answering it takes a
/// wallet signature; a claim in chat never counts (SEC-05).
struct GuardianQuestion: Identifiable, Sendable {
    let id: String
    let dependentID: String
    let title: String
    let amount: Units
    let category: Category
    let askedAgo: String
    let requestText: String
    let agentReasoning: String
    let recommendation: Recommendation
    let recommendedAmount: Units?
    let verdict: AuditorVerdict?
    let reasonCodes: [ReasonCode]
    let hasProof: Bool
}

struct WeeklySummary: Identifiable, Sendable {
    let id: String
    let weekOf: String
    let body: String
    let sent: Units
    let requests: Int
    let flagged: Int
}

/// One link in the append-only, hash-chained log (SPEC §14, SEC-16).
struct AuditLogEntry: Identifiable, Sendable {
    let id: Int
    let event: String
    let detail: String
    let time: String
    let hashPrefix: String
}
