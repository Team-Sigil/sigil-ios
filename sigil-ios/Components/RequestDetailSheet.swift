import SwiftUI

/// Everything about one request: what was asked, what the agent decided and said, the
/// conversation behind it, the receipts sent, and the transfer it produced.
///
/// Opened from any activity row, by the guardian or the dependent. A guardian sees the
/// agent's summary for them and, while the request is still waiting on them, the same
/// signed approve / decline answer as the home screen (SEC-05). A dependent never sees
/// the guardian summary.
struct RequestDetailSheet: View {
    let item: ActivityItem
    let isGuardian: Bool
    /// Takes a dependent to the screen where an owed receipt is sent.
    var onSendReceipt: (() -> Void)?

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var threadState: LoadState = .loading
    @State private var retrying = false
    @State private var retryNote: String?
    @State private var questionState: LoadState = .loaded

    private enum LoadState { case loading, loaded, failed }

    /// The row as the store has it now, so an answer signed here redraws the sheet.
    private var current: ActivityItem {
        store.activity(for: item.dependentID).first { $0.id == item.id } ?? item
    }

    private var thread: [ThreadEntry] { store.threads[item.id] ?? [] }
    private var proofs: [Proof] { store.proofsByRequest[item.id] ?? [] }
    /// The question to answer, only while the request itself is still waiting on the
    /// guardian. Earlier agent runs can leave open questions behind on a request that has
    /// since been paid or declined; answering one of those would be refused, so it isn't
    /// offered. The request's latest decision is what says whether anything is waiting.
    private var openQuestion: GuardianQuestion? {
        guard current.outcome.needsGuardian else { return nil }
        return store.question(forRequest: item.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if isGuardian, openQuestion != nil {
                        LabeledSection(title: "Waiting for you") {
                            ApprovalsSection(requestID: item.id)
                        }
                    } else if isGuardian, current.outcome.needsGuardian {
                        missingQuestion
                    }
                    dependentActions
                    agentNote
                    facts
                    conversation
                    if !proofs.isEmpty { receipts }
                    if let signature = current.txSignature { transaction(signature) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Palette.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Typo.body(15, .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .foregroundStyle(Palette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            async let thread: Void = loadThread()
            async let question: Void = loadQuestionIfMissing()
            _ = await (thread, question)
        }
    }

    // MARK: Guardian question

    /// The request says it is waiting on the guardian, but its question isn't in the store:
    /// the list read failed, or it hasn't been read since the agent asked. Read it now
    /// rather than leave the guardian with nothing to press.
    @ViewBuilder private var missingQuestion: some View {
        switch questionState {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading the question for you…")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        case .failed:
            callout(icon: "exclamationmark.triangle",
                    text: "This is waiting for your answer, but the question couldn't be loaded.") {
                Button("Try again") { Task { await loadQuestionIfMissing() } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        case .loaded:
            callout(icon: "checkmark",
                    text: "There's no open question for this request any more. It may already have been answered.") {
                EmptyView()
            }
        }
    }

    private func loadQuestionIfMissing() async {
        guard isGuardian, current.outcome.needsGuardian, openQuestion == nil else { return }
        questionState = .loading
        let ok = await store.refreshQuestions(familyID: item.dependentID)
        questionState = ok ? .loaded : .failed
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatusBadge(outcome: current.outcome,
                            guardianName: isGuardian ? nil : store.guardianName)
                if current.emergencyClaimed {
                    Text("Emergency")
                        .font(Typo.body(12, .semibold))
                        .foregroundStyle(Palette.orangeInk)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Palette.orangeSoft, in: Capsule())
                }
            }
            Text(current.title)
                .font(Typo.display(24))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 4) {
                Text(amountHeadline)
                    .font(Typo.mono(34))
                    .tracking(-1)
                    .foregroundStyle(current.outcome.isStopped ? Palette.muted : Palette.ink)
                    .strikethrough(current.outcome.isStopped && current.amount > .zero)
                Text(subline)
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    /// What moved if anything did, otherwise what was asked for.
    private var amountHeadline: String {
        if current.outcome.isMoneyMoving, current.amountSent > .zero {
            return current.amountSent.display
        }
        return current.amount > .zero ? current.amount.display : "—"
    }

    private var subline: String {
        var parts: [String] = []
        if isGuardian { parts.append(store.name(of: current.dependentID)) }
        if current.outcome == .sentPartial, current.amountSent > .zero {
            parts.append("of \(current.amount.display) asked")
        }
        parts.append(current.time)
        return parts.joined(separator: " · ")
    }

    // MARK: Dependent

    /// What a dependent can do about a request from here: send an owed receipt, or have
    /// the agent look again at one still waiting. Neither moves money by itself.
    @ViewBuilder private var dependentActions: some View {
        if !isGuardian {
            if store.owesReceipt(request: item.id) {
                callout(
                    icon: "doc.text",
                    text: "A receipt is owed for this. Send it from Home with the app's camera or the shop's PDF."
                ) {
                    if let onSendReceipt {
                        Button("Send the receipt") {
                            dismiss()
                            onSendReceipt()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            } else if current.outcome.needsGuardian {
                // Nothing that runs the agent again: each run on a request waiting for the
                // guardian files another question for them.
                callout(
                    icon: "clock",
                    text: "Waiting for \(store.guardianName). Only their wallet signature can decide it, and you'll see the answer here as soon as they sign."
                ) {
                    EmptyView()
                }
            } else if current.outcome == .safeFallback {
                // The agent never reached a decision (an outage, say), so running it again
                // is the way forward. Money stays safe: transfers are idempotent.
                callout(
                    icon: "arrow.clockwise",
                    text: "The agent couldn't finish this one. You can have it try again."
                ) {
                    Button(retrying ? "Asking the agent…" : "Ask the agent to try again") {
                        retry()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(retrying)
                    if let retryNote {
                        Text(retryNote)
                            .font(Typo.body(12))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
        }
    }

    private func callout<Actions: View>(
        icon: String, text: String, @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Palette.paper, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: 1))
                    .accessibilityHidden(true)
                Text(text)
                    .font(Typo.body(14))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            actions()
        }
        .cardStyle()
    }

    private func retry() {
        Task {
            retrying = true
            retryNote = nil
            defer { retrying = false }
            guard let decision = await store.retry(requestID: item.id) else {
                retryNote = store.problem ?? "The agent didn't answer. Try again in a moment."
                return
            }
            await loadThread()
            if decision.outcome.needsGuardian {
                retryNote = "It's now waiting for \(store.guardianName)."
            }
        }
    }

    // MARK: Agent

    @ViewBuilder private var agentNote: some View {
        let summary = isGuardian ? current.summaryForGuardian : nil
        VStack(alignment: .leading, spacing: 10) {
            if let summary, !summary.isEmpty {
                noteCard(label: "Agent's summary for you", text: summary)
            }
            noteCard(
                label: isGuardian ? "What the agent told \(store.name(of: current.dependentID))" : "The agent's reply",
                text: current.reply
            )
        }
    }

    private func noteCard(label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SigilMark(size: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(Typo.body(12, .semibold))
                    .foregroundStyle(Palette.muted)
                Text(text)
                    .font(Typo.body(14))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    // MARK: Facts

    private var facts: some View {
        LabeledSection(title: "Details") {
            ListCard {
                InfoRow(title: "Asked for", value: current.amount > .zero ? current.amount.display : "—")
                InfoRow(title: "Sent", value: current.amountSent > .zero ? current.amountSent.display : "Nothing")
                InfoRow(title: "Category", value: current.category.label, mono: false)
                InfoRow(title: "Status", value: current.outcome.label, mono: false)
                InfoRow(title: "When", value: current.time, mono: false)
            }
        }
    }

    // MARK: Conversation

    private var conversation: some View {
        LabeledSection(title: "Conversation") {
            switch threadState {
            case .loading where thread.isEmpty:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading the conversation…")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            case .failed where thread.isEmpty:
                HStack(spacing: 10) {
                    Text("Couldn't load the conversation.")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    LinkButton(title: "Try again") { Task { await loadThread() } }
                }
                .cardStyle()
            default:
                if thread.isEmpty {
                    Text("Nothing was said about this one.")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(thread) { entry in
                            bubble(entry)
                        }
                    }
                }
            }
        }
    }

    private func bubble(_ entry: ThreadEntry) -> some View {
        let fromDependent = entry.role == .dependent
        return VStack(alignment: fromDependent ? .trailing : .leading, spacing: 4) {
            Text("\(speaker(entry.role)) · \(entry.at)")
                .font(Typo.body(11, .semibold))
                .foregroundStyle(Palette.muted)
            Text(entry.text)
                .font(Typo.body(14))
                .lineSpacing(2)
                .foregroundStyle(fromDependent ? Palette.paper : Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    fromDependent ? Palette.ink : bubbleFill(entry.role),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    if !fromDependent {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    }
                }
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: fromDependent ? .trailing : .leading)
        .padding(fromDependent ? .leading : .trailing, 36)
    }

    private func speaker(_ role: ThreadRole) -> String {
        switch role {
        case .dependent: isGuardian ? store.name(of: current.dependentID) : "You"
        case .agent: "Agent"
        case .guardianAnswer: isGuardian ? "You" : "Guardian"
        case .systemEvent: "Sigil"
        }
    }

    private func bubbleFill(_ role: ThreadRole) -> Color {
        switch role {
        case .guardianAnswer: Palette.blueSoft
        case .systemEvent: Palette.graySoft
        default: Palette.card
        }
    }

    // MARK: Receipts

    private var receipts: some View {
        LabeledSection(title: "Receipts") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(proofs) { proof in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: proof.isVerifiedCapture ? "camera.fill" : "doc.text.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(proof.kind.rawValue.capitalized)
                                .font(Typo.body(14, .semibold))
                            Spacer()
                            Text("Sent \(proof.uploadedAt)")
                                .font(Typo.body(12))
                                .foregroundStyle(Palette.muted)
                        }
                        if !proof.flags.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(proof.flags, id: \.rawValue) { ProofFlagChip(flag: $0) }
                            }
                        }
                    }
                    .cardStyle(padding: 14)
                }
            }
        }
    }

    // MARK: Transaction

    private func transaction(_ signature: String) -> some View {
        LabeledSection(title: "On chain") {
            VStack(alignment: .leading, spacing: 12) {
                Text(signature)
                    .font(Typo.mono(12, .regular))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if !signature.hasPrefix("mock_"), let url = Chain.explorer(transaction: signature) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Text("View on Solana Explorer").font(Typo.body(14, .semibold))
                            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Palette.ink)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    private func loadThread() async {
        if thread.isEmpty { threadState = .loading }
        let ok = await store.loadThread(item.id, familyID: item.dependentID)
        threadState = ok ? .loaded : .failed
    }
}

/// An activity row that opens the request's detail sheet.
struct TappableActivityRow: View {
    let item: ActivityItem
    var dependentName: String?
    var showsGuardianSummary = false
    let onTap: (ActivityItem) -> Void

    var body: some View {
        Button { onTap(item) } label: {
            HStack(spacing: 8) {
                ActivityRow(item: item, dependentName: dependentName,
                            showsGuardianSummary: showsGuardianSummary)
                Chevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the details")
    }
}
