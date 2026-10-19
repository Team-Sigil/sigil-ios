import SwiftUI

/// Stand-in data for the UI pass. Shapes follow the gateway's App API (its README)
/// and the agent layer's contracts, so the screens can be wired to the real service
/// without changing what they render.
enum MockData {
    // Ids a signed message carries (gateway "Guardian signatures").
    static let nonce = "3c0b…77e4"

    /// One reservoir per guardian, shared by every dependent and backed by a single
    /// Phantom delegation.
    static let guardianTokenAccount = "6Jn2…qW4r"

    static let guardian = Guardian(
        name: "Hnin",
        shortName: "Mom",
        initials: "HN",
        wallet: "4Qm1…kT8v"
    )

    /// `delegated_remaining` is nullable: the chain may simply not be readable.
    static let reservoirRemaining: Units? = Units(1_240)
    static let sentThisMonth = Units(640)
    static let transfersThisMonth = 14

    static let dependents: [Dependent] = [
        Dependent(
            id: "mt", familyID: "8f2c…a91d", name: "Min Thu", initials: "MT", tokenAccount: "9Hq4…2mFe",
            avatarBackground: Palette.blueSoft, avatarForeground: Palette.blueInk,
            sentThisMonth: Units(460), requestsThisMonth: 11, awaitingGuardian: 1
        ),
        Dependent(
            id: "sm", familyID: "1d47…c05e", name: "Su Myat", initials: "SM", tokenAccount: "5Tc9…vB3n",
            avatarBackground: Palette.orangeSoft, avatarForeground: Palette.orangeInk,
            sentThisMonth: Units(180), requestsThisMonth: 19, awaitingGuardian: 0
        ),
        Dependent(
            id: "ak", familyID: "b903…6f12", name: "Aung Kyaw", initials: "AK", tokenAccount: "2Yp7…hL6s",
            avatarBackground: Palette.graySoft, avatarForeground: Palette.ink,
            sentThisMonth: Units(95), requestsThisMonth: 4, awaitingGuardian: 1
        ),
    ]

    static func dependent(_ id: String) -> Dependent {
        dependents.first { $0.id == id } ?? dependents[0]
    }

    static func name(of id: String) -> String {
        dependent(id).name
    }

    static func dependent(familyID: String) -> Dependent {
        dependents.first { $0.familyID == familyID } ?? dependents[0]
    }

    // MARK: Policies

    static let policies: [String: Policy] = [
        "mt": Policy(
            id: "p-mt", dependentID: "mt", version: 3, bodyHash: "a7f3…9c21", activatedAt: "2 Oct",
            body: PolicyBody(
                weeklyCap: Units(150), maxPerRequest: Units(60),
                blockedCategories: [.gaming, .entertainment],
                proofThreshold: Units(50), reviewThreshold: Units(30),
                allowance: Allowance(amount: Units(50), weekday: .mon),
                guidance: """
                Education and study materials are always a priority — don't make him \
                justify a textbook. Clothes are fine occasionally, but question it if \
                they start coming every week. He eats out a lot, so nudge him if food \
                runs past half the week's budget.
                """
            ),
            summary: "Min Thu can get up to $150 a week. Requests up to $60 go out on their own. Anything bigger comes to you first, and anything over $50 needs proof of the price.",
            testScenarios: [
                "If Min Thu asks for $25 of lab supplies, I would send it.",
                "If Min Thu asks for $180 of textbooks, I would ask you first.",
                "If Min Thu asks for a $40 game pass, I would decline — gaming is blocked.",
            ]
        ),
        "sm": Policy(
            id: "p-sm", dependentID: "sm", version: 2, bodyHash: "b41e…77aa", activatedAt: "28 Sep",
            body: PolicyBody(
                weeklyCap: Units(80), maxPerRequest: Units(25),
                blockedCategories: [.entertainment, .gaming],
                proofThreshold: Units(25), reviewThreshold: nil,
                allowance: Allowance(amount: Units(80), weekday: .mon),
                guidance: """
                Daily food and transport are never a problem. She is careful with money, \
                so don't make her justify small amounts.
                """
            ),
            summary: "Su Myat can get up to $80 a week, and her $80 allowance lands every Monday. Requests up to $25 go out on their own; anything bigger comes to you.",
            testScenarios: [
                "If Su Myat asks for $9 for lunch, I would send it.",
                "If Su Myat asks for $60 for a concert, I would decline — entertainment is blocked.",
                "If Su Myat says she needs $40 for a clinic visit, I would ask you straight away.",
            ]
        ),
        "ak": Policy(
            id: "p-ak", dependentID: "ak", version: 1, bodyHash: "c902…14d7", activatedAt: "11 Oct",
            body: PolicyBody(
                weeklyCap: Units(120), maxPerRequest: Units(40),
                blockedCategories: [.gaming],
                proofThreshold: Units(30), reviewThreshold: Units(25),
                allowance: nil,
                guidance: """
                No scheduled allowance — he asks when he needs something. He is new to \
                this, so explain every decision carefully.
                """
            ),
            summary: "Aung Kyaw has no scheduled allowance. He can ask for up to $120 a week, in requests of up to $40, and anything over $30 needs proof of the price.",
            testScenarios: [
                "If Aung Kyaw asks for $35 of groceries, I would send it once he shows me what it costs.",
                "If Aung Kyaw asks for $80 of tools, I would ask you first.",
                "If Aung Kyaw asks for a $12 game pass, I would decline — gaming is blocked.",
            ]
        ),
    ]

    static func policy(for id: String) -> Policy {
        policies[id] ?? policies["mt"]!
    }

    // MARK: Budgets

    static let budgets: [String: Budget] = [
        "mt": Budget(
            spent: Units(95), reserved: .zero, weeklyCap: Units(150), remaining: Units(55),
            delegatedRemaining: reservoirRemaining, resetText: "Resets Mon 20 Oct"
        ),
        "sm": Budget(
            spent: Units(48), reserved: Units(9), weeklyCap: Units(80), remaining: Units(23),
            delegatedRemaining: reservoirRemaining, resetText: "Resets Mon 20 Oct"
        ),
        "ak": Budget(
            spent: Units(35), reserved: .zero, weeklyCap: Units(120), remaining: Units(85),
            delegatedRemaining: reservoirRemaining, resetText: "Resets Mon 20 Oct"
        ),
    ]

    static func budget(for id: String) -> Budget {
        budgets[id] ?? budgets["mt"]!
    }

    /// "Weekly · $150" for a dependent card.
    static func planText(for id: String, short: Bool = false) -> String {
        let policy = policy(for: id)
        let cap = policy.body.weeklyCap.compact
        guard policy.body.allowance != nil else {
            return short ? "On request · \(cap)" : "No allowance · \(cap) cap"
        }
        return short ? "Weekly · \(cap)" : "Weekly cap · \(cap)"
    }

    // MARK: Open questions

    static let questions: [GuardianQuestion] = [
        GuardianQuestion(
            id: "q-1", requestID: "r-91", dependentID: "mt", title: "Textbooks",
            question: "Min Thu wants $180 for two Thermodynamics textbooks. Approve?",
            amount: Units(180), category: .education,
            recommendation: .approve, recommendedAmount: Units(180), urgency: .normal,
            agentView: "Above Min Thu's $60 per-request limit, so I held it for you. Education is a priority in your guidance and the bookstore receipt matches the amount.",
            auditorView: "Agreed. The receipt, the purpose and the category line up, and textbooks fit the guardian's stated priority.",
            askedAgo: "8 min ago", emergencyClaimed: false,
            proofs: [
                Proof(id: "pf-1", kind: .receipt, source: "photo",
                      flags: [.cameraSigned], capturedAt: "Today 18:49", uploadedAt: "Today 18:50"),
            ]
        ),
        GuardianQuestion(
            id: "q-2", requestID: "r-92", dependentID: "ak", title: "Replacement laptop charger",
            question: "Aung Kyaw wants $85 for a laptop charger and says it's urgent. Approve?",
            amount: Units(85), category: .education,
            recommendation: .approve, recommendedAmount: Units(85), urgency: .high,
            agentView: "Over his $40 per-request limit. The reason is plausible and education is a priority, so I'd approve the full amount.",
            auditorView: "Flagged. The message quotes your own guidance back as a reason to skip the limit, and nothing was attached to show the charger or its price.",
            askedAgo: "2 h ago", emergencyClaimed: true,
            proofs: []
        ),
    ]

    // MARK: Activity

    static let activity: [ActivityGroup] = [
        ActivityGroup(label: "Today", items: [
            ActivityItem(
                outcome: .askedGuardian, title: "Textbooks", dependentID: "mt", amount: Units(180),
                category: .education,
                reply: "That's over your $60 per-request limit, so I've asked Mom. She'll see the receipt with it.",
                summaryForGuardian: "Asked you about $180 of textbooks; the receipt matches and the Auditor agreed.",
                time: "8 min"
            ),
            ActivityItem(
                outcome: .sentFull, title: "Lab supplies", dependentID: "mt", amount: Units(25),
                amountSent: Units(25), category: .education,
                reply: "Sent — $25 for lab supplies is well inside your limits this week.",
                time: "12 min", txSignature: "5KJp…8vQa"
            ),
            ActivityItem(
                outcome: .askedProof, title: "Winter jacket", dependentID: "mt", amount: Units(65),
                category: .clothing,
                reply: "Anything over $50 needs proof of the price — show me the price tag in the app and I'll carry on.",
                time: "40 min"
            ),
            ActivityItem(
                outcome: .sentFull, title: "Lunch", dependentID: "sm", amount: Units(9),
                amountSent: Units(9), category: .food,
                reply: "Sent — enjoy lunch.",
                time: "1:20 pm", txSignature: "3Bn7…kR2x"
            ),
            ActivityItem(
                outcome: .auditorFlagged, title: "Replacement laptop charger", dependentID: "ak",
                amount: Units(85), category: .education,
                reply: "This one needs Mom. I've sent her what you told me and my own view.",
                summaryForGuardian: "The Auditor flagged this: the message quotes your guidance back to justify skipping the limit.",
                emergencyClaimed: true, time: "2 h"
            ),
        ]),
        ActivityGroup(label: "Yesterday", items: [
            ActivityItem(
                outcome: .sentFull, title: "Clinic visit", dependentID: "sm", amount: Units(85),
                amountSent: Units(85), category: .health,
                reply: "Mom approved it and it's sent. Hope you feel better.",
                emergencyClaimed: true, time: "6:05 pm", txSignature: "7Wd2…pM4c"
            ),
            ActivityItem(
                outcome: .sentPartial, title: "Groceries and snacks", dependentID: "ak",
                amount: Units(50), amountSent: Units(35), category: .food,
                reply: "I've sent $35 for the groceries. The snacks can wait until next week's budget.",
                time: "11:15 am", txSignature: "9Lk5…tZ7b"
            ),
            ActivityItem(
                outcome: .sentFull, title: "Bus pass", dependentID: "mt", amount: Units(30),
                amountSent: Units(30), category: .transport,
                reply: "Sent — that's your travel sorted for the week.",
                time: "8:40 am", txSignature: "2Vb8…nH9d"
            ),
        ]),
        ActivityGroup(label: "Tue 14 Oct", items: [
            ActivityItem(
                outcome: .blocked, title: "Concert tickets", dependentID: "mt", amount: Units(90),
                category: .entertainment,
                reply: "I can't send this one — entertainment is blocked in your policy. Ask Mom if you'd like that changed.",
                time: "9:12 pm"
            ),
            ActivityItem(
                outcome: .counterOffer, title: "New headphones", dependentID: "mt", amount: Units(70),
                category: .other,
                reply: "There's only $30 left this week. I can send that now, or the full $70 on Monday — your call.",
                time: "7:02 pm"
            ),
            ActivityItem(
                outcome: .sentFull, title: "Groceries", dependentID: "mt", amount: Units(40),
                amountSent: Units(40), category: .food,
                reply: "Sent — $40 for groceries.",
                time: "5:30 pm", txSignature: "6Rf1…yC3k"
            ),
            ActivityItem(
                outcome: .outOfScope, title: "“what's the weather like”", dependentID: "sm",
                amount: .zero, category: .other,
                reply: "I only handle your allowance — I can't help with that one.",
                time: "10:02 am"
            ),
        ]),
    ]

    /// Everything one dependent can see: their own requests, never anyone else's.
    static func history(for id: String) -> [ActivityItem] {
        activity.flatMap(\.items).filter { $0.dependentID == id }
    }

    static let requestPresets: [(label: String, text: String)] = [
        ("Textbooks", "I need $40 for a course textbook"),
        ("Transport", "I need $20 for bus fare this week"),
        ("Groceries", "I need $35 for groceries"),
        ("Phone top-up", "I need $15 to top up my phone"),
    ]

    /// The thread of the request that is waiting on the guardian.
    static let pendingThread: [ThreadEntry] = [
        ThreadEntry(role: .dependent, text: "Need the two textbooks for Thermodynamics, the second-hand ones are gone.", at: "10:02 pm"),
        ThreadEntry(role: .agent, text: "That's over your $60 per-request limit. Can you send me the receipt or the listing?", at: "10:02 pm"),
        ThreadEntry(role: .dependent, text: "Just took a photo of the bookstore receipt.", at: "10:04 pm"),
        ThreadEntry(role: .agent, text: "Thanks — that matches. I've asked Mom and she'll see the receipt with my recommendation.", at: "10:04 pm"),
    ]

    // MARK: Notifications, summaries, audit

    /// `family_id` is null for anything about the guardian as a whole, such as the
    /// shared reservoir; those arrive on every stream and are de-duplicated by id.
    static let notifications: [Notification] = [
        Notification(id: "n-1", familyID: "8f2c…a91d", message: "Min Thu asked for $180 for textbooks.", time: "8 min", isRead: false),
        Notification(id: "n-2", familyID: "b903…6f12", message: "The Auditor flagged Aung Kyaw's $85 charger request.", time: "2 h", isRead: false),
        Notification(id: "n-3", familyID: nil, message: "Your reservoir covers about three more weeks across all three dependents.", time: "Yesterday", isRead: true),
    ]

    static let summaries: [WeeklySummary] = [
        WeeklySummary(
            id: "w-1", weekOf: "Week of 6 Oct",
            body: "Min Thu spent $118 of $150, mostly on study materials. Two requests came to you; you approved both. Nothing was blocked. Su Myat stayed well inside her budget.",
            sent: Units(243), requests: 9, flagged: 1
        ),
        WeeklySummary(
            id: "w-2", weekOf: "Week of 29 Sep",
            body: "A quieter week. One concert request was blocked as entertainment, and Min Thu accepted a smaller amount for clothes without pushing back.",
            sent: Units(186), requests: 7, flagged: 0
        ),
    ]

    static let auditChainValid = true

    static let auditLog: [AuditLogEntry] = [
        AuditLogEntry(id: 2041, event: "decision_recorded", detail: "Textbooks · asked_guardian", time: "18:52", hashPrefix: "e41c…"),
        AuditLogEntry(id: 2040, event: "verdict_recorded", detail: "Textbooks · agree", time: "18:52", hashPrefix: "9b7a…"),
        AuditLogEntry(id: 2039, event: "request_created", detail: "Textbooks · $180.00 · education", time: "18:51", hashPrefix: "22f8…"),
        AuditLogEntry(id: 2038, event: "proof_uploaded", detail: "Receipt · camera_signed", time: "18:50", hashPrefix: "70bd…"),
        AuditLogEntry(id: 2037, event: "transfer_sent", detail: "Lab supplies · 5KJp…8vQa", time: "18:40", hashPrefix: "c105…"),
        AuditLogEntry(id: 2036, event: "policy_activated", detail: "Min Thu · version 3 · a7f3…9c21", time: "2 Oct", hashPrefix: "4a90…"),
    ]
}
