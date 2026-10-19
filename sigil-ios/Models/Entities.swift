import SwiftUI

enum Role: String {
    case guardian, dependent
}

/// Signed-in state shared by the whole app.
///
/// A guardian may support several dependents, each in its own family. Guardian calls
/// about one dependent carry that family in the `X-Family-Id` header, so the selected
/// family is session state, not a screen's local state.
@Observable
final class AppSession {
    var role: Role?

    /// `family_ids` from sign-in, oldest first. Empty for a guardian means onboarding.
    var familyIDs: [String] = []

    /// The family every guardian request is about. Nil until one is chosen.
    var selectedFamilyID: String?

    /// Freeze is per family (SEC-17): "freeze everyone" is one signature each.
    private var frozenFamilies: Set<String> = []

    var needsOnboarding: Bool { role == .guardian && familyIDs.isEmpty }
    var hasSeveralDependents: Bool { familyIDs.count > 1 }

    func isFrozen(_ familyID: String) -> Bool {
        frozenFamilies.contains(familyID)
    }

    func setFrozen(_ frozen: Bool, familyID: String) {
        if frozen {
            frozenFamilies.insert(familyID)
        } else {
            frozenFamilies.remove(familyID)
        }
    }

    var frozenCount: Int { frozenFamilies.count }

    func signIn(as role: Role) {
        withAnimation(.easeInOut(duration: 0.3)) {
            self.role = role
            familyIDs = MockData.dependents.map(\.familyID)
            selectedFamilyID = familyIDs.first
        }
    }

    func signOut() {
        withAnimation(.easeInOut(duration: 0.3)) {
            role = nil
            familyIDs = []
            selectedFamilyID = nil
            frozenFamilies = []
        }
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
    /// Each dependent is their own family, and that id goes in `X-Family-Id`.
    let familyID: String
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
    /// Nil when the notification is about the guardian as a whole, such as the
    /// shared reservoir, rather than one dependent.
    let familyID: String?
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
