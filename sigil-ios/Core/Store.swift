import Foundation
import Observation
import SwiftUI

/// Everything the screens read, loaded from the gateway.
///
/// One store per signed-in person. It turns the API's shapes into the types the screens
/// already use, so a response shape stays the gateway's business and a screen's model
/// stays ours.
@Observable
final class Store {
    private let session: AppSession

    var families: [FamilyDTO] = []
    var budget: Budget?
    var policy: Policy?
    var requests: [ActivityItem] = []
    var obligations: [ProofObligationDTO] = []
    var questions: [GuardianQuestion] = []
    var notifications: [Notification] = []
    var transfers: [TransferDTO] = []

    var loading = false
    /// The last failure, in the gateway's own words.
    var problem: String?

    init(session: AppSession) {
        self.session = session
    }

    /// The dependent of the family currently being acted on.
    var selectedFamily: FamilyDTO? {
        families.first { $0.id == session.selectedFamilyID } ?? families.first
    }

    var owesReceipt: ProofObligationDTO? { obligations.first }

    // MARK: Loading

    /// Everything the current screen set needs. Called on appear and on pull to refresh.
    @MainActor
    func load() async {
        guard session.signedIn else { return }
        loading = true
        defer { loading = false }
        let api = session.api

        // The guardian's families decide which family the rest of the calls are about, so
        // they come first and alone.
        if session.role == .guardian {
            families = (try? await api.families()) ?? []
            if session.selectedFamilyID == nil {
                session.selectedFamilyID = families.first?.id
            }
        }
        guard session.selectedFamilyID != nil || session.role == .dependent else { return }

        let scoped = session.api
        async let budgetTask = try? scoped.budget()
        async let policyTask = try? scoped.activePolicy()
        async let requestsTask = try? scoped.requests()
        async let obligationsTask = try? scoped.proofObligations()
        async let notificationsTask = try? scoped.notifications()
        async let historyTask = try? scoped.history()

        budget = await budgetTask.map(Budget.init)
        policy = await policyTask.map { Policy($0, dependentID: session.selectedFamilyID ?? "") }
        requests = await (requestsTask ?? []).map(ActivityItem.init)
        obligations = await obligationsTask ?? []
        notifications = await (notificationsTask ?? []).map(Notification.init)
        transfers = await historyTask?.transfers ?? []

        if session.role == .guardian {
            questions = await ((try? scoped.questions()) ?? []).map(GuardianQuestion.init)
        }
    }

    // MARK: Asking

    /// Creates a request and waits for the agent, which the gateway allows up to 150 s.
    @MainActor
    func ask(amount: Units, category: Category, purpose: String, emergency: Bool) async -> Decision? {
        problem = nil
        let text = purpose.isEmpty
            ? "I need \(amount.compact) for \(category.label.lowercased())."
            : "I need \(amount.compact) for \(purpose) (\(category.label.lowercased()))."
        do {
            let processed = try await session.api.createRequest(
                message: text, amount: amount, emergency: emergency
            )
            await load()
            return Decision(processed.decision)
        } catch let error as APIError {
            problem = error.readable
            return nil
        } catch {
            problem = "Couldn't reach the gateway."
            return nil
        }
    }

    // MARK: Signed guardian actions

    /// Answers a question with the guardian's signature. The gateway rebuilds the text from
    /// its own records, so this has to match byte for byte.
    @MainActor
    func answer(_ question: GuardianQuestion, approve: Bool, amount: Units?) async -> Bool {
        await signed(purpose: "answer-question") { nonce, family in
            SignedMessage.answerQuestion(
                family: family, question: question.id, approve: approve,
                amount: approve ? amount : nil, nonce: nonce
            )
        } call: { api, nonce, signature in
            _ = try await api.answerQuestion(
                id: question.id, approve: approve, amount: amount,
                note: nil, nonce: nonce, signature: signature
            )
        }
    }

    @MainActor
    func setFrozen(_ frozen: Bool) async -> Bool {
        await signed(purpose: "freeze") { nonce, family in
            SignedMessage.freeze(family: family, frozen: frozen, nonce: nonce)
        } call: { api, nonce, signature in
            _ = try await api.freeze(frozen: frozen, nonce: nonce, signature: signature)
        }
    }

    /// Registers a dependent. Every dependent of a guardian shares one reservoir, so the
    /// token account must be the one the guardian's other families already use.
    @MainActor
    func registerDependent(
        wallet: String, tokenAccount: String, guardianTokenAccount: String, name: String
    ) async -> Bool {
        let ok = await signed(purpose: "register-dependent") { nonce, _ in
            SignedMessage.registerDependent(
                wallet: wallet, tokenAccount: tokenAccount, nonce: nonce
            )
        } call: { api, nonce, signature in
            let registered = try await api.registerFamily(
                dependentWallet: wallet,
                dependentTokenAccount: tokenAccount,
                guardianTokenAccount: guardianTokenAccount,
                dependentName: name,
                nonce: nonce,
                signature: signature
            )
            await MainActor.run { self.session.adopt(registered) }
        }
        if ok { await load() }
        return ok
    }

    /// The shape every signed action takes: a nonce for that purpose, the exact text, the
    /// wallet's signature, then the call.
    @MainActor
    private func signed(
        purpose: String,
        message: (_ nonce: String, _ family: String) -> String,
        call: (SigilAPI, String, String) async throws -> Void
    ) async -> Bool {
        problem = nil
        do {
            let api = session.api
            let address = try session.signer.address
            let nonce = try await api.nonce(wallet: address, purpose: purpose).nonce
            let family = session.selectedFamilyID ?? ""
            let signature = try session.signer.sign(message(nonce, family))
            try await call(api, nonce, signature)
            await load()
            return true
        } catch let error as APIError {
            problem = error.readable
            return false
        } catch {
            problem = "Couldn't reach the gateway."
            return false
        }
    }
}

// MARK: - Turning responses into what the screens read

extension Budget {
    init(_ dto: BudgetDTO) {
        self.init(
            spent: Units(raw: dto.spent),
            reserved: Units(raw: dto.reserved),
            weeklyCap: Units(raw: dto.weeklyCap),
            remaining: Units(raw: dto.remaining),
            delegatedRemaining: dto.delegatedRemaining.map(Units.init(raw:)),
            resetText: "Resets \(Self.weekReset(dto.weekStart))"
        )
    }

    /// "Mon 20 Oct" from the week's Monday.
    private static func weekReset(_ weekStart: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let monday = parser.date(from: weekStart),
              let next = Calendar.current.date(byAdding: .day, value: 7, to: monday) else {
            return weekStart
        }
        let display = DateFormatter()
        display.dateFormat = "E d MMM"
        return display.string(from: next)
    }
}

extension Policy {
    init(_ dto: ActivePolicyDTO, dependentID: String) {
        self.init(
            id: dto.id,
            dependentID: dependentID,
            version: dto.version,
            bodyHash: dto.bodyHash ?? "",
            activatedAt: dto.activatedAt.map(Self.shortDate) ?? "",
            body: PolicyBody(dto.body),
            summary: "",
            testScenarios: []
        )
    }

    static func shortDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let display = DateFormatter()
        display.dateFormat = "d MMM"
        return display.string(from: date)
    }
}

extension PolicyBody {
    init(_ dto: PolicyBodyDTO) {
        self.init(
            weeklyCap: Units(raw: dto.weeklyCap),
            maxPerRequest: Units(raw: dto.maxPerRequest),
            blockedCategories: dto.blockedCategories.compactMap(Category.init(rawValue:)),
            proofThreshold: Units(raw: dto.proofThreshold),
            reviewThreshold: dto.reviewThreshold.map(Units.init(raw:)),
            allowance: dto.allowance.map {
                Allowance(amount: Units(raw: $0.amount), weekday: Weekday(index: $0.weekday))
            },
            guidance: dto.guidance ?? ""
        )
    }
}

extension Decision {
    init(_ dto: DecisionDTO) {
        self.init(
            outcome: Outcome(apiValue: dto.outcome),
            replyToDependent: dto.replyToDependent,
            amountSent: Units(raw: dto.amountSent),
            transferID: dto.transferId,
            summaryForGuardian: dto.summaryForGuardian
        )
    }
}

extension ActivityItem {
    /// A request as a row. The gateway's list endpoint carries the request without its
    /// decisions, so the outcome comes from what was sent against what was asked.
    init(_ dto: RequestDTO) {
        let asked = dto.amountRequested.map(Units.init(raw:)) ?? .zero
        let sent = Units(raw: dto.alreadySent)
        let outcome: Outcome =
            if sent >= asked, sent > .zero { .sentFull }
            else if sent > .zero { .sentPartial }
            else { .askedGuardian }
        self.init(
            outcome: outcome,
            title: dto.message,
            dependentID: "",
            amount: asked,
            amountSent: sent,
            category: .other,
            reply: dto.message,
            emergencyClaimed: dto.emergencyClaimed,
            time: Policy.shortDate(dto.createdAt)
        )
    }
}

extension GuardianQuestion {
    init(_ dto: QuestionDTO) {
        self.init(
            id: dto.id,
            requestID: dto.requestId,
            dependentID: "",
            title: dto.question,
            question: dto.question,
            amount: dto.recommendedAmount.map(Units.init(raw:)) ?? .zero,
            category: .other,
            recommendation: Recommendation(apiValue: dto.recommendation),
            recommendedAmount: dto.recommendedAmount.map(Units.init(raw:)),
            urgency: Urgency(apiValue: dto.urgency),
            agentView: dto.agentView,
            auditorView: dto.auditorView,
            askedAgo: Policy.shortDate(dto.createdAt),
            emergencyClaimed: false,
            proofs: []
        )
    }
}

extension Notification {
    init(_ dto: NotificationDTO) {
        self.init(
            id: dto.id,
            familyID: dto.familyId,
            message: dto.message,
            time: Policy.shortDate(dto.createdAt),
            isRead: dto.readAt != nil
        )
    }
}
