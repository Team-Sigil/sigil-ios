import Foundation

/// SPEC §6.5. The list is fixed: a category the guardian invents cannot reach the engine.
enum Category: String, CaseIterable, Identifiable, Sendable {
    case food, transport, education, health, housing, clothing
    case entertainment, gaming, gambling, subscriptions, gifts, emergency, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .food: "Food"
        case .transport: "Transport"
        case .education: "Education"
        case .health: "Health"
        case .housing: "Housing"
        case .clothing: "Clothing"
        case .entertainment: "Entertainment"
        case .gaming: "Gaming"
        case .gambling: "Gambling"
        case .subscriptions: "Subscriptions"
        case .gifts: "Gifts"
        case .emergency: "Emergency"
        case .other: "Other"
        }
    }
}

enum Cadence: String, Sendable {
    case weekly, none

    var label: String {
        switch self {
        case .weekly: "Weekly"
        case .none: "On request only"
        }
    }
}

enum Weekday: String, CaseIterable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun

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

/// The outer limits the engine enforces (SPEC §7). Code checks these; it never
/// interprets `Policy.guidance`.
struct Limits: Sendable {
    var weeklyCap: Units
    var maxPerRequest: Units
    var blockedCategories: [Category]
    var proofThreshold: Units
    var auditThreshold: Units
    var lowConfidenceThreshold: Double
    var maxRequestsPerDay: Int
}

struct Allowance: Sendable {
    var amount: Units
    var cadence: Cadence
    var weekday: Weekday
}

/// One signed, versioned policy. A policy only counts once the guardian has
/// signed `bodyHash` with their wallet (SPEC §7, SEC-04).
struct Policy: Identifiable, Sendable {
    let id: String
    let dependentID: String
    let version: Int
    let bodyHash: String
    let activatedAt: String
    var limits: Limits
    var allowance: Allowance
    /// Plain-language intent the agent interprets. Never enforced by code, and
    /// never shown to the dependent (SPEC §17, SEC-10).
    var guidance: [String]
    /// The agent's plain-language rendering of the policy, shown before signing.
    var summary: String
    /// "If X asks for Y, I would Z" — the guardian corrects these before signing.
    var testCases: [String]
}
