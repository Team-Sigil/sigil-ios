import SwiftUI

/// Every open question, each with the two answers a guardian can give.
///
/// Shared by the home and activity screens. A question is the only thing in the app that
/// actually needs the guardian, so it has to be reachable wherever they go looking for it,
/// and *all* of them have to be — showing only the first leaves the rest unanswerable.
///
/// Answering is a wallet signature over the gateway's own text, never a tap (SEC-05). The
/// engine treats the signed amount as the override, so the amount is settled before the
/// signature sheet opens and never changes afterwards.
struct ApprovalsSection: View {
    /// Shown when nothing is waiting and nothing has just been answered. Nil renders
    /// nothing at all, for a screen where the section should simply disappear.
    var emptyMessage: String?
    /// Set to show only the question about one request, as the request's detail sheet does.
    var requestID: String?

    @Environment(Store.self) private var store
    @State private var answering: PendingAnswer?
    @State private var notice: Notice?

    /// An answer the guardian has chosen but not yet signed.
    private struct PendingAnswer: Identifiable {
        let question: GuardianQuestion
        let approve: Bool
        let amount: Units?
        let nonce: String
        var id: String { "\(question.id)-\(approve)" }
    }

    private struct Notice: Equatable {
        let approved: Bool
        let text: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice {
                noticeBanner(notice)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            ForEach(visibleQuestions) { question in
                QuestionCard(
                    question: question,
                    dependentName: store.name(of: question.dependentID),
                    onDecline: { prepare(question, approve: false) },
                    onApprove: { prepare(question, approve: true) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            if visibleQuestions.isEmpty, notice == nil, let emptyMessage {
                nothingWaiting(emptyMessage)
            }
        }
        .sheet(item: $answering) { pending in
            SignatureSheet(
                title: pending.approve
                    ? "Approve \(pending.amount?.compact ?? "")"
                    : "Decline this request",
                summary: pending.approve
                    ? "Your wallet approves exactly this amount for \(store.name(of: pending.question.dependentID)). It can pass the per-request and weekly limits, and nothing else."
                    : "\(store.name(of: pending.question.dependentID)) is told you declined, and no money moves.",
                message: [
                    "FinGuard:answer-question",
                    "family:\(pending.question.dependentID)",
                    "question:\(pending.question.id)",
                    "decision:\(pending.approve ? "approve" : "deny")",
                    "amount_units:\(pending.amount.map { String($0.raw) } ?? "none")",
                    "nonce:\(pending.nonce)",
                ],
                confirmTitle: pending.approve ? "Sign and approve" : "Sign and decline"
            ) {
                answer(pending)
            }
        }
    }

    private var visibleQuestions: [GuardianQuestion] {
        guard let requestID else { return store.questions }
        return store.questions.filter { $0.requestID == requestID }
    }

    /// Shown when the agent is handling everything itself, which is the normal state.
    private func nothingWaiting(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.paper)
                .frame(width: 36, height: 36)
                .background(Palette.ink, in: Circle())
                .accessibilityHidden(true)
            Text(message)
                .font(Typo.body(14))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, -2)
        .cardStyle(padding: 14)
    }

    private func noticeBanner(_ notice: Notice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notice.approved ? "checkmark" : "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.paper)
                .frame(width: 36, height: 36)
                .background(Palette.ink, in: Circle())
                .accessibilityHidden(true)
            Text(notice.text)
                .font(Typo.body(14))
                .frame(maxWidth: .infinity, alignment: .leading)
            // A signed answer is final: the gateway has recorded it and the agent has
            // already acted on it, so there is nothing to undo.
            LinkButton(title: "Done") {
                withAnimation(.snappy) { self.notice = nil }
            }
        }
        .padding(.vertical, -2)
        .cardStyle(padding: 14)
    }

    private static func noticeText(_ pending: PendingAnswer, next: Decision?, name: String) -> String {
        let signed = pending.approve
            ? "Approved \(pending.amount?.compact ?? "") and signed."
            : "Declined and signed."
        guard let next else {
            return "\(signed) The agent couldn't run just now; it will act on your answer when it does."
        }
        switch next.outcome {
        case .sentFull, .sentPartial:
            return "\(signed) \(next.amountSent.compact) was sent to \(name)."
        case .transferPending:
            return "\(signed) \(next.amountSent.compact) is on its way to \(name)."
        case .declined:
            return "\(signed) \(name) has been told."
        default:
            return "\(signed) \(next.summaryForGuardian ?? next.replyToDependent)"
        }
    }

    /// Chooses the answer and takes a nonce for it, then shows the guardian the exact text
    /// their wallet will sign. A nonce is single use and 5 minutes old at most, so it is
    /// taken per attempt and never reused (SEC-09).
    private func prepare(_ question: GuardianQuestion, approve: Bool) {
        Task {
            let amount = approve ? (question.recommendedAmount ?? question.amount) : nil
            guard let nonce = await store.nonce(
                purpose: "answer-question", family: question.dependentID
            ) else { return }
            answering = PendingAnswer(
                question: question, approve: approve, amount: amount, nonce: nonce
            )
        }
    }

    private func answer(_ pending: PendingAnswer) {
        Task {
            let result = await store.answer(
                pending.question,
                approve: pending.approve,
                amount: pending.amount,
                nonce: pending.nonce
            )
            guard let next = result else {
                // Cancelled in Phantom leaves no problem; anything else says what went wrong.
                if let problem = store.problem {
                    withAnimation(.snappy) { notice = Notice(approved: false, text: problem) }
                }
                return
            }
            // The store has already reloaded, so the card is gone: the outcome is reported
            // here rather than in the card that produced it, from what the agent did next.
            withAnimation(.snappy) {
                notice = Notice(
                    approved: pending.approve,
                    text: Self.noticeText(pending, next: next, name: store.name(of: pending.question.dependentID))
                )
            }
        }
    }
}

/// One open question: who is asking, for how much, what the agent and the auditor make of
/// it, and anything the integrity checks flagged on the receipt.
private struct QuestionCard: View {
    let question: GuardianQuestion
    let dependentName: String
    let onDecline: () -> Void
    let onApprove: () -> Void

    @Environment(Store.self) private var store

    /// What the checks said about the proofs attached, worth seeing before deciding.
    private var flags: [ProofFlag] {
        var seen: Set<String> = []
        return question.proofs.flatMap(\.flags).filter { seen.insert($0.rawValue).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                let dependent = store.dependent(familyID: question.dependentID)
                Avatar(initials: dependent?.initials ?? "?",
                       background: dependent?.avatarBackground ?? Palette.graySoft,
                       foreground: dependent?.avatarForeground ?? Palette.ink, fontSize: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(dependentName) · \(question.title)")
                        .font(Typo.body(15, .semibold))
                    Text("Requested \(question.askedAgo)")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(question.amount.display).font(Typo.mono(20)).tracking(-0.4)
            }

            if question.emergencyClaimed {
                Text("Claimed as an emergency")
                    .font(Typo.body(12, .semibold))
                    .foregroundStyle(Palette.orangeInk)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Palette.orangeSoft, in: Capsule())
            }

            HStack(alignment: .top, spacing: 10) {
                SigilMark(size: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Text("Agent:").bold().foregroundStyle(Palette.ink)) \(question.agentView)")
                    Text(question.recommendation.label)
                        .font(Typo.body(12, .semibold))
                        .foregroundStyle(Palette.muted)
                }
                .font(Typo.body(13))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let auditorView = question.auditorView {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "flag")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.orangeInk)
                        .padding(.top, 1)
                    Text("\(Text("Auditor:").bold().foregroundStyle(Palette.orangeDeep)) \(auditorView)")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.orangeInk)
                        .lineSpacing(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.orangeSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !flags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(flags, id: \.rawValue) { flag in
                        ProofFlagChip(flag: flag)
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Decline", action: onDecline)
                    .buttonStyle(SecondaryButtonStyle())
                Button("Approve \(question.amount.compact)", action: onApprove)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .cardStyle()
    }
}
