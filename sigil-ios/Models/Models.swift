import SwiftUI

enum Role {
    case guardian, student
}

/// Signed-in state shared by the whole app.
@Observable
final class AppSession {
    var role: Role?

    /// The guardian's signed kill switch (SPEC §15 SEC-17). While frozen the engine
    /// refuses every transfer, so the whole app reads this one flag.
    var frozen = false

    func signIn(as role: Role) {
        withAnimation(.easeInOut(duration: 0.3)) { self.role = role }
    }

    func signOut() {
        withAnimation(.easeInOut(duration: 0.3)) { role = nil }
    }
}

enum DecisionKind: String, Hashable {
    case sent, held, emergency, declined, pending
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let kind: DecisionKind
    let title: String
    let who: String
    let reason: String
    let amount: String
    let time: String
}

struct ActivityGroup: Identifiable {
    let id = UUID()
    let label: String
    let items: [ActivityItem]
}

struct Dependent: Identifiable {
    let id: String
    let initials: String
    let name: String
    let plan: String
    let shortPlan: String
    let avatarBackground: Color
    let avatarForeground: Color
    let periodLabel: String
    let usedText: String
    let shortUsedText: String
    let fraction: Double
    let resetText: String
    let month: String
    let requests: String
    let awaiting: String
    let awaitingHighlighted: Bool
}

struct PolicySummary {
    let summary: String
    let allowance: String
    let frequency: String
    let reset: String
    let autoUpTo: String
    let perDay: String
}

struct StudentRequest: Identifiable {
    let id = UUID()
    let kind: DecisionKind
    let title: String
    let reason: String
    let amount: String
}

enum MockData {
    /// Stand-ins for the ids a signed message carries (SPEC §8.4).
    static let familyID = "8f2c…a91d"
    static let nonce = "3c0b…77e4"
    static let guardianWallet = "4Qm1…kT8v"

    static let dependents: [Dependent] = [
        Dependent(
            id: "mt", initials: "MT", name: "Min Thu",
            plan: "Weekly plan · $150", shortPlan: "Weekly · $150",
            avatarBackground: Palette.blueSoft, avatarForeground: Palette.blueInk,
            periodLabel: "This week", usedText: "$120 of $150", shortUsedText: "$120 / $150 used",
            fraction: 0.8, resetText: "Resets Mon 20 Oct",
            month: "$460", requests: "11", awaiting: "1", awaitingHighlighted: true
        ),
        Dependent(
            id: "sm", initials: "SM", name: "Su Myat",
            plan: "Daily plan · $15", shortPlan: "Daily · $15",
            avatarBackground: Palette.orangeSoft, avatarForeground: Palette.orangeInk,
            periodLabel: "Today", usedText: "$9 of $15", shortUsedText: "$9 / $15 today",
            fraction: 0.6, resetText: "Resets at midnight",
            month: "$180", requests: "19", awaiting: "0", awaitingHighlighted: false
        ),
    ]

    static let policies: [String: PolicySummary] = [
        "mt": PolicySummary(
            summary: "Min Thu can get up to $150 a week. Requests up to $60 are sent automatically. Anything bigger comes to you first.",
            allowance: "$150", frequency: "Weekly", reset: "Monday", autoUpTo: "$60", perDay: "3"
        ),
        "sm": PolicySummary(
            summary: "Su Myat can get up to $15 a day. Every request inside that is sent automatically. Anything bigger comes to you first.",
            allowance: "$15", frequency: "Daily", reset: "Midnight", autoUpTo: "$15", perDay: "2"
        ),
    ]

    static let blocked: [String: [String]] = [
        "mt": ["Gambling", "Alcohol", "Nightlife & events"],
        "sm": ["Gambling", "Alcohol"],
    ]

    static let activity: [ActivityGroup] = [
        ActivityGroup(label: "Today", items: [
            ActivityItem(kind: .held, title: "Textbooks", who: "Min Thu", reason: "Held: over the $60 per-request limit", amount: "$180.00", time: "8 min"),
            ActivityItem(kind: .sent, title: "Lab supplies", who: "Min Thu", reason: "Auto-sent, within limits", amount: "$25.00", time: "12 min"),
            ActivityItem(kind: .sent, title: "Lunch", who: "Su Myat", reason: "Auto-sent, daily allowance", amount: "$9.00", time: "1:20 pm"),
        ]),
        ActivityGroup(label: "Yesterday", items: [
            ActivityItem(kind: .emergency, title: "Clinic visit", who: "Su Myat", reason: "Emergency category · Auditor reviewed · you approved", amount: "$85.00", time: "6:05 pm"),
            ActivityItem(kind: .sent, title: "Bus pass", who: "Min Thu", reason: "Auto-sent, within limits", amount: "$30.00", time: "8:40 am"),
        ]),
        ActivityGroup(label: "Tue 14 Oct", items: [
            ActivityItem(kind: .declined, title: "Concert tickets", who: "Min Thu", reason: "Declined: Nightlife & events is blocked", amount: "$90.00", time: "9:12 pm"),
            ActivityItem(kind: .sent, title: "Groceries", who: "Min Thu", reason: "Auto-sent, within limits", amount: "$40.00", time: "5:30 pm"),
            ActivityItem(kind: .sent, title: "Phone top-up", who: "Su Myat", reason: "Auto-sent, daily allowance", amount: "$6.00", time: "10:02 am"),
        ]),
    ]

    static let studentHistory: [StudentRequest] = [
        StudentRequest(kind: .sent, title: "Lab supplies", reason: "Sent in seconds · within your limits · Today", amount: "$25.00"),
        StudentRequest(kind: .sent, title: "Bus pass", reason: "Sent in seconds · within your limits · Yesterday", amount: "$30.00"),
        StudentRequest(kind: .declined, title: "Concert tickets", reason: "Nightlife & events isn’t allowed by your policy · Tue", amount: "$90.00"),
        StudentRequest(kind: .sent, title: "Groceries", reason: "Sent in seconds · within your limits · Tue", amount: "$40.00"),
        StudentRequest(kind: .sent, title: "Coffee & snacks", reason: "Sent in seconds · within your limits · Mon", amount: "$12.00"),
        StudentRequest(kind: .sent, title: "Printing", reason: "Sent in seconds · within your limits · Mon", amount: "$13.00"),
    ]

    static let requestPresets: [(label: String, text: String)] = [
        ("Textbooks", "I need $40 for a course textbook"),
        ("Transport", "I need $20 for bus fare this week"),
        ("Groceries", "I need $35 for groceries"),
        ("Phone bill", "I need $15 to top up my phone"),
    ]
}
