import Foundation

/// The categories the agent layer actually uses (`contracts/agent.py`).
///
/// These replace the longer list in SPEC §6.5: the gateway README is explicit that
/// where SPEC and the service contracts differ on categories, field names, outcomes
/// or the review rule, the contracts win. Note there is no `emergency` category —
/// an emergency is a flag on the request, not a kind of spending.
enum Category: String, CaseIterable, Identifiable, Sendable {
    case education, food, transport, health, clothing
    case entertainment, gaming, savings, allowance, other

    var id: String { rawValue }

    /// `allowance` is the scheduled payment's own category and cannot be blocked.
    static var blockable: [Category] { allCases.filter { $0 != .allowance } }

    var label: String {
        switch self {
        case .education: "Education"
        case .food: "Food"
        case .transport: "Transport"
        case .health: "Health"
        case .clothing: "Clothing"
        case .entertainment: "Entertainment"
        case .gaming: "Gaming"
        case .savings: "Savings"
        case .allowance: "Allowance"
        case .other: "Other"
        }
    }
}

enum Weekday: String, CaseIterable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun

    /// The gateway stores the weekday as an int, 0 = Monday.
    init(index: Int) {
        self = Weekday.allCases.indices.contains(index) ? Weekday.allCases[index] : .mon
    }

    var index: Int {
        Weekday.allCases.firstIndex(of: self) ?? 0
    }

    var label: String {
        switch self {
        case .mon: "Monday"
        case .tue: "Tuesday"
        case .wed: "Wednesday"
        case .thu: "Thursday"
        case .fri: "Friday"
        case .sat: "Saturday"
        case .sun: "Sunday"
        }
    }
}

/// A scheduled allowance. Absent entirely when the guardian doesn't want one.
struct Allowance: Sendable {
    var amount: Units
    var weekday: Weekday
}

/// `PolicyBody` from `contracts/policy.py` — the exact object whose hash the
/// guardian's wallet signs.
struct PolicyBody: Sendable {
    var weeklyCap: Units
    var maxPerRequest: Units
    var blockedCategories: [Category]
    var proofThreshold: Units
    /// Absent means the engine uses 25% of the weekly cap.
    var reviewThreshold: Units?
    var allowance: Allowance?
    /// One block of plain language, not a list — at most 4,000 characters. The agent
    /// interprets it; code never enforces it; the dependent never sees it.
    var guidance: String

    /// What the engine will actually review at, once the default is applied.
    var effectiveReviewThreshold: Units {
        reviewThreshold ?? Units(raw: weeklyCap.raw / 4)
    }

    var usesDefaultReviewThreshold: Bool { reviewThreshold == nil }
}

/// A signed, versioned policy as the app reads it back.
struct Policy: Identifiable, Sendable {
    let id: String
    let dependentID: String
    let version: Int
    let bodyHash: String
    let activatedAt: String
    var body: PolicyBody
    /// The agent's plain-language rendering, shown before signing.
    var summary: String
    /// "If X asks for Y, I would Z" — `draft.test_scenarios` from the interview.
    var testScenarios: [String]
}
