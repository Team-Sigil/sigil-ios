import Foundation
import Observation
import SwiftUI

/// Everything the screens read, loaded from the gateway.
///
/// One store per signed-in person. It turns the API's shapes into the types the screens
/// already use, so a response shape stays the gateway's business and a screen's model
/// stays ours.
@MainActor
@Observable
final class Store {
    private let session: AppSession

    // MARK: What the screens read

    var families: [FamilyDTO] = []
    var dependents: [Dependent] = []
    var questions: [GuardianQuestion] = []
    var notifications: [Notification] = []
    var proposals: [ProposalDTO] = []
    var auditEntries: [AuditLogEntry] = []
    var auditChainValid = true

    /// Per family, so the guardian's lists can show every dependent at once.
    var budgets: [String: Budget] = [:]
    var policies: [String: Policy] = [:]
    var activityByFamily: [String: [ActivityItem]] = [:]
    var obligationsByFamily: [String: [ProofObligation]] = [:]

    /// One request's conversation, fetched when a screen shows it.
    var threads: [String: [ThreadEntry]] = [:]
    /// Receipts attached to a request, loaded with its thread.
    var proofsByRequest: [String: [Proof]] = [:]
    /// Request details already read, by request id. The gateway allows 30 calls a minute per
    /// session, so a settled request is read once and kept, rather than on every reload.
    private var detailCache: [String: RequestDetailDTO] = [:]
    /// Whose reads the cache holds. A guardian's details carry their summaries, so nothing
    /// cached survives into another wallet's session on the same device.
    private var cacheOwner: String?

    var loading = false
    /// The last failure, in the gateway's own words.
    var problem: String?

    private let events = EventStream()
    /// Collapses a burst of events into one reload.
    private var pendingReload: Task<Void, Never>?

    init(session: AppSession) {
        self.session = session
    }

    /// Follows the gateway's live events, so a decision made while a screen is open shows
    /// up without the person doing anything.
    func listen() {
        guard session.signedIn, !families.isEmpty else { return }
        events.listen(
            families: families.map(\.id),
            api: { [session] familyID in session.api(for: familyID) },
            onEvent: { [weak self] in self?.reloadSoon() }
        )
    }

    func stopListening() {
        events.stop()
        pendingReload?.cancel()
    }

    private func reloadSoon() {
        pendingReload?.cancel()
        pendingReload = Task {
            // Events come in bursts (a question, a message, a transfer), and every reload
            // costs a dozen calls against a 30-a-minute limit, so a burst is one reload.
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    // MARK: Lookups the screens use

    var guardian: Guardian {
        Guardian(wallet: session.wallet ?? "", displayName: session.displayName)
    }

    /// What a dependent calls their guardian. The gateway tells a dependent nothing about
    /// their guardian beyond the wallet, so the copy stays neutral rather than inventing
    /// a name.
    var guardianName: String { "your guardian" }

    /// The dependent whose family guardian calls are currently about.
    var selected: Dependent? {
        dependents.first { $0.familyID == session.selectedFamilyID } ?? dependents.first
    }

    /// The signed-in dependent themselves.
    var me: Dependent? { dependents.first }

    func dependent(familyID: String) -> Dependent? {
        dependents.first { $0.familyID == familyID }
    }

    /// The name the guardian gave this dependent, if they gave one. Unlike `name(of:)`
    /// this doesn't fall back to a slice of their wallet, because a suggested sentence
    /// reading "This is for 9Hq4" helps nobody.
    func dependentName(of familyID: String) -> String? {
        let given = families.first { $0.id == familyID }?.dependentName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (given?.isEmpty ?? true) ? nil : given
    }

    func name(of familyID: String) -> String {
        dependent(familyID: familyID)?.name ?? "your dependent"
    }

    func budget(for familyID: String) -> Budget? { budgets[familyID] }

    /// "Weekly · ฿150" for a dependent card.
    func planText(for familyID: String, short: Bool = false) -> String {
        guard let policy = policy(for: familyID) else {
            return short ? "No policy yet" : "No policy set yet"
        }
        let cap = policy.body.weeklyCap.compact
        guard policy.body.allowance != nil else {
            return short ? "On request · \(cap)" : "No allowance · \(cap) cap"
        }
        return short ? "Weekly · \(cap)" : "Weekly cap · \(cap)"
    }
    func policy(for familyID: String) -> Policy? { policies[familyID] }
    func activity(for familyID: String) -> [ActivityItem] { activityByFamily[familyID] ?? [] }
    func obligations(for familyID: String) -> [ProofObligation] {
        obligationsByFamily[familyID] ?? []
    }

    /// How many receipts may be owed at once before the gateway stops sending more money
    /// for requests. Mirrors `MAX_OPEN_OBLIGATIONS` in the gateway; it is a server rule,
    /// not a preference, and the app API does not publish it.
    static let maxOwedReceipts = 3

    /// The receipts this dependent owes, oldest first. Each is money already paid out, so
    /// each is a task to clear rather than a warning: asking is only refused with
    /// `409 PROOF_OUTSTANDING` once `maxOwedReceipts` of them are open.
    var owedReceipts: [ProofObligation] {
        guard let family = session.selectedFamilyID ?? families.first?.id else { return [] }
        return obligations(for: family)
    }

    /// True when asking for money will be refused until a receipt is sent.
    var owedReceiptsAreBlocking: Bool { owedReceipts.count >= Self.maxOwedReceipts }

    /// Whether this particular request is one of the ones still owing a receipt.
    func owesReceipt(request requestID: String) -> Bool {
        obligationsByFamily.values.flatMap { $0 }.contains { $0.requestID == requestID }
    }

    /// Everything, newest first, across the guardian's dependents.
    var allActivity: [ActivityItem] {
        activityByFamily.values.flatMap { $0 }
            .sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
    }

    /// The activity list grouped into the day headings the screens show.
    var activityGroups: [ActivityGroup] {
        let items = allActivity
        var order: [String] = []
        var grouped: [String: [ActivityItem]] = [:]
        for item in items {
            let label = item.at.map { Dates.dayLabel($0) } ?? "Earlier"
            if grouped[label] == nil { order.append(label) }
            grouped[label, default: []].append(item)
        }
        return order.map { ActivityGroup(label: $0, items: grouped[$0] ?? []) }
    }

    /// Everything one dependent can see: their own requests, never anyone else's.
    func history(forFamily familyID: String?) -> [ActivityItem] {
        guard let familyID = familyID ?? families.first?.id else { return [] }
        return activity(for: familyID)
    }

    var sentThisMonth: Units {
        Units(raw: dependents.reduce(0) { $0 + $1.sentThisMonth.raw })
    }

    var transfersThisMonth: Int {
        dependents.reduce(0) { $0 + $1.requestsThisMonth }
    }

    /// The shared reservoir, after money in flight for any dependent. Nil when the chain
    /// could not be read, which the screens must show as unknown.
    var reservoirRemaining: Units? {
        budgets.values.compactMap(\.delegatedRemaining).first
    }

    /// The guardian's reservoir: the account their existing dependents already draw on,
    /// or the aUSD account of their own wallet when there are none yet.
    var guardianTokenAccount: String {
        if let registered = families.first?.guardianTokenAccount { return registered }
        guard let wallet = session.wallet else { return "" }
        return TokenAccount.of(wallet: wallet) ?? ""
    }

    // MARK: Loading

    /// The load in flight, if any. Launch alone asks for two (the session restore and the
    /// tab view appearing), and two at once are ~36 calls against the gateway's 30 a
    /// minute: the overflow is refused and whatever it was (the open questions, say)
    /// silently goes missing. So a load already running is joined, not repeated.
    private var inflightLoad: Task<Void, Never>?

    /// Everything the current screen set needs. Called on appear and after any change.
    func load() async {
        if let inflightLoad {
            await inflightLoad.value
            return
        }
        let task = Task { await performLoad() }
        inflightLoad = task
        await task.value
        inflightLoad = nil
    }

    private func performLoad() async {
        guard session.signedIn else { return }
        if cacheOwner != session.wallet {
            detailCache = [:]
            threads = [:]
            proofsByRequest = [:]
            cacheOwner = session.wallet
        }
        loading = true
        defer { loading = false }

        do {
            // Roles are read from the database on every request, so a wallet that was
            // registered as a dependent after signing in becomes one without signing in
            // again. Asking who we are first keeps the app on the right side.
            if let me = try? await session.api.me() {
                session.adopt(me)
            }
            let api = session.api
            if session.role == .guardian {
                families = try await api.families()
            } else {
                families = [try await api.family()]
            }
            session.applyFrozen(families)
            if session.selectedFamilyID == nil
                || !families.contains(where: { $0.id == session.selectedFamilyID }) {
                session.selectedFamilyID = families.first?.id
            }
        } catch let error as APIError {
            problem = error.readable
            return
        } catch {
            problem = "Couldn't reach the gateway."
            return
        }

        await withTaskGroup(of: (String, FamilyLoad?).self) { group in
            for family in families {
                let api = session.api(for: family.id)
                let isGuardian = session.role == .guardian
                let cached = detailCache
                group.addTask {
                    (family.id, await Self.loadFamily(api: api, asGuardian: isGuardian, cached: cached))
                }
            }
            for await (familyID, loaded) in group {
                guard let loaded else { continue }
                apply(loaded, to: familyID)
            }
        }

        rebuildDependents()

        if session.role == .guardian {
            let api = session.api
            notifications = ((try? await api.notifications()) ?? []).map(Notification.init)
            proposals = (try? await api.proposals()) ?? []
        } else {
            notifications = ((try? await session.api.notifications()) ?? []).map(Notification.init)
        }

        listen()
    }

    /// One family's reads, which are all scoped by the `X-Family-Id` header.
    private struct FamilyLoad {
        var budget: Budget?
        var policy: Policy?
        // Nil means the read failed (a 429, say), and what is on screen stays: a failed
        // read is not the same as nothing waiting.
        var activity: [ActivityItem]?
        var obligations: [ProofObligation]?
        var questions: [GuardianQuestion]?
        var sentThisMonth: Units = .zero
        var requestsThisMonth = 0
        var details: [String: RequestDetailDTO] = [:]
    }

    /// At most this many request details are read per family per load, newest first, so a
    /// reload stays well inside the gateway's rate limit. Anything not read this time keeps
    /// its cached detail and is read on a later load.
    private static let maxDetailReads = 8

    /// Whether a request's detail can still change without its `already_sent` changing:
    /// anything still waiting on someone, or with a receipt still owed.
    private static func isSettled(_ detail: RequestDetailDTO, request: RequestDTO,
                                  owing: Set<String>) -> Bool {
        guard detail.alreadySent == request.alreadySent, !owing.contains(request.id),
              let outcome = detail.decision.map({ Outcome(apiValue: $0.outcome) }) else {
            return false
        }
        switch outcome {
        case .sentFull, .sentPartial, .declined, .blocked, .outOfScope,
             .receiptAccepted, .receiptRejected:
            return true
        default:
            return false
        }
    }

    /// Stays on the main actor: every step here is awaited network I/O, which suspends
    /// rather than blocking, and the work it does in between is assembling small structs.
    private static func loadFamily(
        api: SigilAPI, asGuardian: Bool, cached: [String: RequestDetailDTO]
    ) async -> FamilyLoad? {
        async let budgetTask = try? api.budget()
        async let policyTask = try? api.activePolicy()
        async let requestsTask = try? api.requests()
        async let historyTask = try? api.history()
        async let obligationsTask = try? api.proofObligations()
        async let questionsTask = asGuardian ? try? api.questions() : []

        var loaded = FamilyLoad()
        loaded.budget = await budgetTask.map(Budget.init)
        if let dto = await policyTask {
            loaded.policy = Policy(dto, familyID: api.familyID ?? "")
        }

        let fetchedRequests = await requestsTask
        let requests = fetchedRequests ?? []
        let history = await historyTask
        let transfers = history?.transfers ?? []
        let transfersByRequest = Dictionary(
            transfers.compactMap { transfer in transfer.requestId.map { ($0, transfer) } },
            // The latest transfer is the one the latest decision is about.
            uniquingKeysWith: { a, b in
                (Dates.parse(a.createdAt) ?? .distantPast) >= (Dates.parse(b.createdAt) ?? .distantPast) ? a : b
            }
        )

        let fetchedObligations = await obligationsTask
        let obligations = fetchedObligations ?? []
        let owing = Set(obligations.map(\.requestId))

        // The list endpoint carries no decisions, and `GET /history` carries no reply, so
        // the rows come from each request's own detail. Settled ones come from the cache;
        // the rest are read, newest first, and a read that fails (a 429, say) falls back to
        // what was cached rather than losing the decision.
        var details: [String: RequestDetailDTO] = [:]
        var toRead: [String] = []
        let newestFirst = requests.sorted {
            (Dates.parse($0.createdAt) ?? .distantPast) > (Dates.parse($1.createdAt) ?? .distantPast)
        }
        for request in newestFirst {
            if let detail = cached[request.id] {
                details[request.id] = detail
                if isSettled(detail, request: request, owing: owing) { continue }
            }
            toRead.append(request.id)
        }
        await withTaskGroup(of: RequestDetailDTO?.self) { group in
            for id in toRead.prefix(maxDetailReads) {
                group.addTask { try? await api.request(id: id) }
            }
            for await detail in group {
                if let detail { details[detail.id] = detail }
            }
        }
        loaded.details = details

        loaded.activity = fetchedRequests == nil ? nil : requests.compactMap { request in
            ActivityItem(
                request: request,
                detail: details[request.id],
                transfer: transfersByRequest[request.id],
                familyID: api.familyID ?? ""
            )
        }

        let monthStart = Dates.monthStart()
        loaded.sentThisMonth = Units(
            raw: transfers
                .filter { $0.status == "sent" }
                .filter { (Dates.parse($0.createdAt) ?? .distantPast) >= monthStart }
                .reduce(0) { $0 + $1.amount }
        )
        loaded.requestsThisMonth = requests
            .filter { (Dates.parse($0.createdAt) ?? .distantPast) >= monthStart }
            .count

        loaded.obligations = fetchedObligations == nil ? nil : obligations.map { dto in
            ProofObligation(
                id: dto.id,
                requestID: dto.requestId,
                transferID: dto.transferId,
                amount: Units(raw: dto.amount),
                title: details[dto.requestId].map { ActivityItem.title(from: $0.message) }
                    ?? "money already sent",
                sentAgo: Dates.ago(dto.createdAt)
            )
        }

        loaded.questions = (await questionsTask)?.map { dto in
            GuardianQuestion(
                dto,
                familyID: api.familyID ?? "",
                request: dto.requestId.flatMap { details[$0] }
            )
        }
        return loaded
    }

    private func apply(_ loaded: FamilyLoad, to familyID: String) {
        if let budget = loaded.budget { budgets[familyID] = budget }
        if let policy = loaded.policy { policies[familyID] = policy }
        if let activity = loaded.activity {
            activityByFamily[familyID] = activity
            monthly[familyID] = (loaded.sentThisMonth, loaded.requestsThisMonth)
        }
        if let obligations = loaded.obligations { obligationsByFamily[familyID] = obligations }
        detailCache.merge(loaded.details) { _, new in new }
        if let loadedQuestions = loaded.questions {
            replaceQuestions(loadedQuestions, of: familyID)
        }
    }

    /// One card per request. Each agent run on a waiting request can file another open
    /// question about it, and only the newest reflects the request as it stands now.
    private func replaceQuestions(_ new: [GuardianQuestion], of familyID: String) {
        questions.removeAll { $0.dependentID == familyID }
        questions.append(contentsOf: new)
        questions.sort { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
        var seen: Set<String> = []
        questions = questions.filter { question in
            guard let requestID = question.requestID else { return true }
            return seen.insert(requestID).inserted
        }
    }

    /// Reads only one family's open questions: one call, for a screen that knows a request
    /// is waiting on the guardian but has no question for it.
    @discardableResult
    func refreshQuestions(familyID: String) async -> Bool {
        guard session.role == .guardian,
              let dtos = try? await session.api(for: familyID).questions() else { return false }
        replaceQuestions(dtos.map { dto in
            GuardianQuestion(dto, familyID: familyID,
                             request: dto.requestId.flatMap { detailCache[$0] })
        }, of: familyID)
        return true
    }

    /// Per family: what went out this month and how many times it was asked.
    private var monthly: [String: (sent: Units, requests: Int)] = [:]

    private func rebuildDependents() {
        dependents = families.enumerated().map { index, family in
            Dependent(
                family,
                index: index,
                sentThisMonth: monthly[family.id]?.sent ?? .zero,
                requestsThisMonth: monthly[family.id]?.requests ?? 0,
                awaitingGuardian: questions.filter { $0.dependentID == family.id }.count
            )
        }
    }

    /// The thread of one request: what was said, by whom, in order.
    /// A guardian may have several families, so the request is read under its own one.
    @discardableResult
    func loadThread(_ requestID: String, familyID: String? = nil) async -> Bool {
        let api = familyID.map { session.api(for: $0) } ?? session.api
        guard let detail = try? await api.request(id: requestID) else { return false }
        detailCache[requestID] = detail
        threads[requestID] = detail.thread.map(ThreadEntry.init)
        proofsByRequest[requestID] = detail.proofs.map(Proof.init)
        return true
    }

    /// The open question about a request, if the guardian still has to answer it.
    func question(forRequest requestID: String) -> GuardianQuestion? {
        questions.first { $0.requestID == requestID }
    }

    /// The guardian's wallet, which is all a dependent is told about them.
    var guardianWallet: String { families.first?.guardianWallet ?? "" }

    func loadAudit() async {
        guard let trail = try? await session.api.audit() else { return }
        auditChainValid = trail.chainValid
        auditEntries = trail.entries.reversed().map { entry in
            AuditLogEntry(
                id: entry.id,
                event: entry.eventType,
                detail: Self.auditDetail(entry),
                time: Dates.clock(entry.createdAt),
                hashPrefix: String(entry.hash.prefix(4)) + "…"
            )
        }
    }

    private static func auditDetail(_ entry: AuditEntryDTO) -> String {
        let interesting = ["amount", "category", "outcome", "version", "verdict", "status"]
        let parts = interesting.compactMap { key -> String? in
            guard let value = entry.payload[key]?.text, !value.isEmpty else { return nil }
            if key == "amount", let raw = Int64(value) { return Units(raw: raw).display }
            return value
        }
        return parts.isEmpty ? entry.eventType.replacingOccurrences(of: "_", with: " ")
            : parts.joined(separator: " · ")
    }

    // MARK: Asking

    /// Creates a request and waits for the agent, which the gateway allows up to 150 s.
    func ask(
        amount: Units, category: Category, purpose: String, emergency: Bool
    ) async -> (request: String, decision: Decision)? {
        problem = nil
        let what = purpose.isEmpty ? category.label.lowercased() : purpose
        let text = "I need \(amount.compact) for \(what)."
        do {
            let processed = try await session.api.createRequest(
                message: text, amount: amount, emergency: emergency
            )
            await load()
            return (processed.request.id, Decision(processed.decision))
        } catch let error as APIError {
            problem = error.readable
            return nil
        } catch {
            problem = "Couldn't reach the gateway."
            return nil
        }
    }

    /// A follow-up on the same request: taking a smaller offer, or asking for the guardian.
    func follow(up requestID: String, message: String, amount: Units? = nil) async -> Decision? {
        problem = nil
        do {
            let processed = try await session.api.addMessage(
                to: requestID, message: message, amount: amount
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

    /// Runs the agent again on a request that was stored while the agent was unavailable.
    func retry(requestID: String) async -> Decision? {
        problem = nil
        guard let processed = try? await session.api.process(requestID: requestID) else {
            problem = "The agent still isn't answering."
            return nil
        }
        await load()
        return Decision(processed.decision)
    }

    /// What came back from sending a receipt. The gateway decides all of this: whether the
    /// file counts as evidence at all, and whether the obligation it was sent against is
    /// settled (SPEC §8.9).
    enum ProofResult {
        case accepted(Decision?)
        /// Stored, but worth nothing as evidence — an unsigned PDF, say.
        case notEvidence(String)
        /// The gateway read the receipt and refused it: not the full amount, already used,
        /// not a usable photo. The reason is the agent's own words.
        case rejected(String, Decision?)
        /// Nothing usable was attached, so the receipt is still owed.
        case stillOwed(Decision?)
        case failed(String)
    }

    /// Sends a receipt for a request, as a verified in-app capture when the device can do
    /// one, and as a plain file when it cannot.
    func sendProof(
        requestID: String, data: Data, filename: String, mediaType: String, verified: Bool
    ) async -> ProofResult {
        problem = nil
        // The gateway sends a PDF to the agent exactly as uploaded, and the agent reads at
        // most 5 MB, so a bigger one is refused there. Say so before spending the upload.
        let limit = mediaType == "application/pdf" ? 5 * 1_024 * 1_024 : 15 * 1_024 * 1_024
        guard data.count <= limit else {
            let size = mediaType == "application/pdf" ? "5 MB" : "15 MB"
            return .failed("That file is too big — receipts can be up to \(size).")
        }
        let api = session.api
        var claim: String?
        var signature: String?

        // A capture is only "verified" if every step works. If attestation isn't available
        // — the simulator, a device the gateway won't enrol — the receipt still goes, as a
        // plain file that the agent treats more carefully.
        if verified, VerifiedCapture.isSupported {
            do {
                let device = try await VerifiedCapture.device(api: api)
                let ticket = try await api.captureTicket(
                    requestID: requestID, deviceID: device.deviceID
                )
                let signed = try await VerifiedCapture.sign(
                    image: data, ticket: ticket.ticket, requestID: requestID,
                    keyID: device.keyID
                )
                claim = signed.claim
                signature = signed.signature
            } catch let error as APIError where error.code == "ATTESTATION_FAILED" {
                VerifiedCapture.forget()
            } catch {
                // Falls through to a plain upload.
            }
        }

        do {
            let uploaded = try await api.uploadProof(
                requestID: requestID,
                data: data,
                filename: filename,
                mediaType: mediaType,
                kind: "receipt",
                captureClaim: claim,
                captureSignature: signature
            )
            await load()
            let decision = Decision(uploaded.decision)
            if uploaded.proof.flags.contains("unchecked_document") {
                return .notEvidence(
                    "That PDF isn't signed by the shop, so I can't use it. Ask them for the signed copy, or photograph a paper receipt."
                )
            }
            // Uploading against a request that owes a receipt runs a receipt check, and
            // its outcome is the gateway's verdict. Trusted over re-reading the
            // obligations, which races with this very upload settling one.
            switch decision.outcome {
            case .receiptAccepted:
                return .accepted(decision)
            case .receiptRejected:
                return .rejected(decision.replyToDependent, decision)
            case .askedProof:
                return .stillOwed(decision)
            default:
                return owesReceipt(request: requestID)
                    ? .stillOwed(decision) : .accepted(decision)
            }
        } catch let error as APIError {
            problem = error.readable
            return .failed(error.readable)
        } catch {
            return .failed("Couldn't send that receipt.")
        }
    }

    func markRead(_ notification: Notification) async {
        try? await session.api.markRead(notification: notification.id)
        notifications = ((try? await session.api.notifications()) ?? []).map(Notification.init)
    }

    // MARK: The delegation

    /// What came back from approving or revoking. The chain is the last word, so success
    /// means the token account itself says so — not that the wallet claimed to send it.
    enum DelegationResult: Equatable {
        case done(signature: String)
        case cancelled
        case failed(String)
    }

    /// What the chain says about the guardian's reservoir right now.
    var reservoir: Devnet.Delegation?

    func loadReservoir() async {
        let account = guardianTokenAccount
        guard !account.isEmpty else { return }
        reservoir = await Devnet.delegation(of: account)
    }

    /// Lets the agent wallet spend up to `amount` from the guardian's reservoir.
    ///
    /// An approval **replaces** whatever was delegated before, so this is always the new
    /// total, never an addition. Nothing about it goes through the gateway: the engine
    /// reads the delegation from the chain before every transfer.
    func approveDelegation(amount: Units) async -> DelegationResult {
        await sendDelegation { owner, reservoir, blockhash in
            SolanaTransaction.approveChecked(
                reservoir: reservoir,
                mint: TokenAccount.mint,
                delegate: Chain.agentWallet,
                owner: owner,
                amount: UInt64(amount.raw),
                decimals: Chain.decimals,
                blockhash: blockhash
            )
        } verify: { delegation in
            delegation.delegate == Chain.agentWallet
                && delegation.delegatedAmount == UInt64(amount.raw)
        }
    }

    /// Takes the delegation back. Nothing can move afterwards until it is approved again.
    func revokeDelegation() async -> DelegationResult {
        await sendDelegation { owner, reservoir, blockhash in
            SolanaTransaction.revoke(
                reservoir: reservoir, owner: owner, blockhash: blockhash
            )
        } verify: { delegation in
            delegation.delegate == nil || delegation.delegatedAmount == 0
        }
    }

    /// Build, let the wallet sign and send, wait for the chain, then check the result on
    /// the account itself.
    private func sendDelegation(
        build: (_ owner: String, _ reservoir: String, _ blockhash: String) -> String?,
        verify: @escaping (Devnet.Delegation) -> Bool
    ) async -> DelegationResult {
        problem = nil
        let account = guardianTokenAccount
        guard !account.isEmpty else {
            return .failed("Your reservoir isn't known yet.")
        }
        do {
            let owner = try await session.signer.connect()
            // Fetched here rather than earlier: a blockhash is stale within about a minute.
            guard let blockhash = await Devnet.latestBlockhash() else {
                return .failed("Couldn't reach devnet. Try again in a moment.")
            }
            guard let transaction = build(owner, account, blockhash) else {
                return .failed("That transaction couldn't be built.")
            }
            // Phantom signs; the app submits. Its signAndSendTransaction deeplink was
            // retired ("This method is not supported") and only ever reached mainnet.
            let signed = try await Phantom.shared.signTransaction(transaction)
            let signature: String
            switch await Devnet.send(signedTransaction: signed) {
            case .accepted(let accepted):
                signature = accepted
            case .expired:
                // The approval screen has a minute or so before the blockhash dies. The
                // amount is still on screen, so tapping Approve again is the whole fix.
                return .failed("That took a moment too long to approve. Tap Approve again.")
            case .rejected(let reason):
                return .failed(reason)
            case .unreachable:
                return .failed("Couldn't reach devnet to send it. Try again in a moment.")
            }

            switch await Devnet.confirm(signature: signature) {
            case false:
                return .failed("The network rejected it.")
            case nil:
                return .failed("It hasn't confirmed yet. Check the explorer in a moment.")
            default:
                break
            }
            await loadReservoir()
            guard let reservoir, verify(reservoir) else {
                return .failed("It went through, but the account doesn't show it yet.")
            }
            await load()
            return .done(signature: signature)
        } catch PhantomError.cancelled {
            return .cancelled
        } catch let error as PhantomError {
            return .failed(error.readable)
        } catch {
            return .failed("Couldn't reach your wallet.")
        }
    }

    // MARK: Signed guardian actions

    /// A single-use nonce for one purpose, fetched before the guardian is shown what they
    /// are about to sign. It lasts 5 minutes and a failed attempt burns it (SEC-09), so one
    /// is taken per attempt and never reused.
    func nonce(purpose: String, family familyID: String? = nil) async -> String? {
        problem = nil
        do {
            let api = session.api(for: familyID ?? session.selectedFamilyID ?? "")
            let address = try await session.signer.connect()
            return try await api.nonce(wallet: address, purpose: purpose).nonce
        } catch let error as APIError {
            problem = error.readable
            return nil
        } catch {
            problem = "Couldn't reach the gateway."
            return nil
        }
    }

    /// Answers a question with the guardian's signature. The gateway rebuilds the text
    /// from its own records, so this has to match byte for byte (SEC-05).
    /// Nil when nothing was recorded (cancelled in Phantom, or refused); otherwise the
    /// agent's next move, which the gateway runs straight after the answer. That decision
    /// is nil only when the agent couldn't run, and the answer still stands.
    func answer(
        _ question: GuardianQuestion, approve: Bool, amount: Units?, nonce: String? = nil
    ) async -> Decision?? {
        var next: Decision?
        let ok = await signed(
            purpose: "answer-question", family: question.dependentID, nonce: nonce
        ) { nonce, family in
            SignedMessage.answerQuestion(
                family: family, question: question.id, approve: approve,
                amount: approve ? amount : nil, nonce: nonce
            )
        } call: { api, nonce, signature in
            let answered = try await api.answerQuestion(
                id: question.id, approve: approve, amount: approve ? amount : nil,
                note: nil, nonce: nonce, signature: signature
            )
            next = answered.decision.map(Decision.init)
        }
        return ok ? .some(next) : nil
    }

    func setFrozen(_ frozen: Bool, familyID: String, nonce: String? = nil) async -> Bool {
        let ok = await signed(purpose: "freeze", family: familyID, nonce: nonce) { nonce, family in
            SignedMessage.freeze(family: family, frozen: frozen, nonce: nonce)
        } call: { api, nonce, signature in
            _ = try await api.freeze(frozen: frozen, nonce: nonce, signature: signature)
        }
        if ok { session.setFrozen(frozen, familyID: familyID) }
        return ok
    }

    /// Registers a dependent. All of a guardian's dependents share one reservoir, so the
    /// token account must be the one their other families already use.
    func registerDependent(
        wallet: String, tokenAccount: String, guardianTokenAccount: String, name: String
    ) async -> Bool {
        problem = nil
        guard Base58.isPubkey(wallet) else {
            problem = "That doesn't look like a wallet address."
            return false
        }
        do {
            let api = session.api
            let address = try await session.signer.connect()
            let nonce = try await api.nonce(wallet: address, purpose: "register-dependent").nonce
            let text = SignedMessage.registerDependent(
                wallet: wallet, tokenAccount: tokenAccount, nonce: nonce
            )
            let registered = try await api.registerFamily(
                dependentWallet: wallet,
                dependentTokenAccount: tokenAccount,
                guardianTokenAccount: guardianTokenAccount,
                dependentName: name,
                nonce: nonce,
                signature: try await session.signer.sign(text)
            )
            session.adopt(registered)
            await load()
            return true
        } catch PhantomError.cancelled {
            return false
        } catch let error as PhantomError {
            problem = error.readable
            return false
        } catch let error as APIError {
            problem = error.readable
            return false
        } catch {
            problem = "Couldn't reach the gateway."
            return false
        }
    }

    /// Activates a draft by signing its version and hash. Nothing the agent drafted takes
    /// effect until this signature (SEC-04).
    func activate(draft: DraftViewDTO) async -> Bool {
        let ok = await signed(purpose: "activate-policy", family: session.selectedFamilyID) {
            nonce, family in
            SignedMessage.activatePolicy(
                family: family, version: draft.version, hash: draft.bodyHash, nonce: nonce
            )
        } call: { api, nonce, signature in
            _ = try await api.activateDraft(id: draft.id, nonce: nonce, signature: signature)
        }
        if ok {
            // The gateway's active policy carries no scenarios, so the ones the guardian
            // read before signing are kept against the hash they signed.
            PolicyExtras.remember(draft)
        }
        return ok
    }

    /// The shape every signed action takes: a nonce for that purpose, the exact text, the
    /// wallet's signature, then the call.
    private func signed(
        purpose: String,
        family familyID: String?,
        nonce prefetched: String? = nil,
        message: (_ nonce: String, _ family: String) -> String,
        call: (SigilAPI, String, String) async throws -> Void
    ) async -> Bool {
        problem = nil
        guard let familyID else {
            problem = "Choose which dependent this is about."
            return false
        }
        do {
            let api = session.api(for: familyID)
            let address = try await session.signer.connect()
            let nonce: String
            if let prefetched {
                nonce = prefetched
            } else {
                nonce = try await api.nonce(wallet: address, purpose: purpose).nonce
            }
            let signature = try await session.signer.sign(message(nonce, familyID))
            try await call(api, nonce, signature)
            await load()
            return true
        } catch PhantomError.cancelled {
            return false
        } catch let error as PhantomError {
            problem = error.readable
            return false
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

@MainActor
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
        guard let monday = Dates.formatter("yyyy-MM-dd").date(from: weekStart),
              let next = Dates.gregorian.date(byAdding: .day, value: 7, to: monday) else {
            return weekStart
        }
        return Dates.formatter("E d MMM").string(from: next)
    }
}

@MainActor
extension Policy {
    init(_ dto: ActivePolicyDTO, familyID: String) {
        let body = PolicyBody(dto.body)
        self.init(
            id: dto.id,
            dependentID: familyID,
            version: dto.version,
            bodyHash: dto.bodyHash ?? "",
            activatedAt: Dates.short(dto.activatedAt),
            body: body,
            summary: Policy.summarise(body),
            testScenarios: PolicyExtras.scenarios(forHash: dto.bodyHash)
        )
    }

    /// The signed limits in plain words.
    ///
    /// `GET /policy/active` returns the limits and nothing else — the agent's own summary
    /// is not stored — so this renders exactly what was signed rather than inventing
    /// anything about it.
    static func summarise(_ body: PolicyBody) -> String {
        var sentences: [String] = ["Up to \(body.weeklyCap.compact) a week."]
        if let allowance = body.allowance {
            sentences.append(
                "The \(allowance.amount.compact) allowance lands every \(allowance.weekday.label)."
            )
        }
        sentences.append(
            "Requests up to \(body.maxPerRequest.compact) go out on their own; anything bigger comes to you first."
        )
        sentences.append("Anything from \(body.proofThreshold.compact) needs a receipt afterwards.")
        if !body.blockedCategories.isEmpty {
            let names = body.blockedCategories.map { $0.label.lowercased() }
                .joined(separator: " and ")
            sentences.append("Never for \(names).")
        }
        return sentences.joined(separator: " ")
    }
}

@MainActor
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

@MainActor
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

@MainActor
extension ActivityItem {
    /// A request as a row: what was asked, what the agent decided and said, and the
    /// transfer it produced.
    init?(
        request: RequestDTO,
        detail: RequestDetailDTO?,
        transfer: TransferDTO?,
        familyID: String
    ) {
        let decision = detail?.decision
        let asked = request.amountRequested.map(Units.init(raw:)) ?? .zero
        var sent = Units(raw: max(decision?.amountSent ?? 0, request.alreadySent))
        // No decision is not the same as money on its way: only the gateway's own
        // `transfer_pending` may say that.
        var outcome = decision.map { Outcome(apiValue: $0.outcome) } ?? .awaitingDecision
        var reply = decision?.replyToDependent ?? "Still being looked at."

        // A decision is a record of the agent's run and is never rewritten, so one that
        // ended `transfer_pending` stays that way after the gateway's retry job settles the
        // transfer. The transfer's own status is the truth about where the money is.
        if outcome == .transferPending, let transfer {
            switch TransferStatus(rawValue: transfer.status) {
            case .sent:
                sent = max(sent, Units(raw: transfer.amount))
                outcome = asked > .zero && sent < asked ? .sentPartial : .sentFull
            case .failed, .blocked:
                outcome = .blocked
                reply = "The transfer didn't go through, so no money moved."
            case .pending, nil:
                break
            }
        }

        self.init(
            id: request.id,
            outcome: outcome,
            title: Self.title(from: request.message),
            dependentID: familyID,
            amount: asked,
            amountSent: sent,
            category: transfer.flatMap { Category(rawValue: $0.category) } ?? .other,
            reply: reply,
            summaryForGuardian: decision?.summaryForGuardian,
            emergencyClaimed: request.emergencyClaimed,
            time: Dates.ago(request.createdAt),
            txSignature: transfer?.txSignature,
            at: Dates.parse(request.createdAt)
        )
    }

    /// Rows show a short phrase, not a whole message, so the first clause is used.
    static func title(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        guard firstLine.count > 46 else { return firstLine }
        let cut = firstLine.prefix(46)
        let lastSpace = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[cut.startIndex..<lastSpace]) + "…"
    }
}

@MainActor
extension GuardianQuestion {
    init(_ dto: QuestionDTO, familyID: String, request: RequestDetailDTO?) {
        self.init(
            id: dto.id,
            requestID: dto.requestId,
            dependentID: familyID,
            title: request.map { ActivityItem.title(from: $0.message) } ?? "A request",
            question: dto.question,
            amount: Units(
                raw: dto.recommendedAmount ?? request?.amountRequested ?? 0
            ),
            category: .other,
            recommendation: Recommendation(apiValue: dto.recommendation),
            recommendedAmount: dto.recommendedAmount.map(Units.init(raw:)),
            urgency: Urgency(apiValue: dto.urgency),
            agentView: dto.agentView,
            auditorView: dto.auditorView,
            askedAgo: Dates.ago(dto.createdAt),
            emergencyClaimed: request?.emergencyClaimed ?? false,
            proofs: (request?.proofs ?? []).map(Proof.init),
            at: Dates.parse(dto.createdAt)
        )
    }
}

@MainActor
extension Proof {
    init(_ dto: ProofDTO) {
        self.init(
            id: dto.id,
            kind: ProofKind(rawValue: dto.kind) ?? .receipt,
            source: dto.source,
            flags: dto.flags.map(ProofFlag.init(apiValue:)),
            capturedAt: dto.capturedAt.map { Dates.clock($0) },
            uploadedAt: Dates.clock(dto.uploadedAt)
        )
    }
}

@MainActor
extension Notification {
    init(_ dto: NotificationDTO) {
        self.init(
            id: dto.id,
            familyID: dto.familyId,
            message: dto.message,
            time: Dates.ago(dto.createdAt),
            isRead: dto.readAt != nil
        )
    }
}

@MainActor
extension ThreadEntry {
    init(_ dto: ThreadEntryDTO) {
        self.init(
            role: ThreadRole(rawValue: dto.role) ?? .systemEvent,
            text: dto.text,
            at: Dates.clock(dto.at)
        )
    }
}

@MainActor
extension Dependent {
    /// A family as the screens show its dependent. Colours are assigned by position so
    /// the same person keeps the same one between launches.
    init(
        _ family: FamilyDTO,
        index: Int,
        sentThisMonth: Units,
        requestsThisMonth: Int,
        awaitingGuardian: Int
    ) {
        let palette: [(Color, Color)] = [
            (Palette.blueSoft, Palette.blueInk),
            (Palette.orangeSoft, Palette.orangeInk),
            (Palette.graySoft, Palette.ink),
        ]
        let colours = palette[index % palette.count]
        let name = family.dependentName ?? String(family.dependentWallet.prefix(4))
        self.init(
            id: family.id,
            familyID: family.id,
            name: name,
            initials: Guardian.initials(of: name),
            tokenAccount: family.dependentTokenAccount,
            avatarBackground: colours.0,
            avatarForeground: colours.1,
            sentThisMonth: sentThisMonth,
            requestsThisMonth: requestsThisMonth,
            awaitingGuardian: awaitingGuardian
        )
    }
}

/// What the gateway doesn't keep.
///
/// `GET /policy/active` returns the signed limits only, but the guardian read the agent's
/// "if X asks for Y, I would Z" scenarios before signing. They are kept against the hash
/// that was signed, so they can only ever be shown next to the exact policy they describe.
enum PolicyExtras {
    private static let key = "sigil.policy.scenarios"

    static func remember(_ draft: DraftViewDTO) {
        var all = stored()
        all[draft.bodyHash] = draft.testScenarios.map(\.sentence)
        UserDefaults.standard.set(all, forKey: key)
    }

    static func scenarios(forHash hash: String?) -> [String] {
        guard let hash else { return [] }
        return stored()[hash] ?? []
    }

    private static func stored() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }
}
