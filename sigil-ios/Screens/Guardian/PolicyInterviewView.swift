import SwiftUI

/// Setting the policy by talking to the agent.
///
/// The guardian answers in their own words; the gateway stores every turn and the agent
/// drafts the limits. The app can only ever send the guardian's own message — there is no
/// way to submit an agent turn — so the "ready" state the signing step depends on cannot
/// be faked from here. Nothing takes effect until the guardian signs the draft's hash
/// (SEC-04).
struct PolicyInterviewView: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The latest turn from the agent, however it was reached: a fresh question, an
    /// answer to the guardian's last message, or an interview that was already under way
    /// when this screen opened.
    @State private var question: String?
    @State private var checklist: [ChecklistItemDTO] = []
    @State private var progress: InterviewProgressDTO?
    @State private var draft: DraftViewDTO?
    @State private var turnsUsed = 0
    @State private var maxTurns = 50
    @State private var started = false
    /// True until the guardian's first message is stored. The opening question is a fixed
    /// phrase that asks who the policy is for, although the gateway already knows, so the
    /// answer box starts with that part filled in — as editable text, not something sent
    /// behind the guardian's back.
    @State private var awaitingFirstAnswer = false
    @State private var suggested = false

    @State private var answer = ""
    @State private var thinking = false
    @State private var signing = false
    @State private var problem: String?
    @State private var retryable = false
    @State private var lastMessage: String?
    @FocusState private var answerFocused: Bool

    var body: some View {
        Screen(spacing: 20) {
            PageTitle(title: title,
                      subtitle: "Answer in your own words. Nothing is live until you sign it.")

            if !checklist.isEmpty || progress != nil {
                progressCard
            }

            if let draft {
                ready(draft)
            } else if started {
                questionCard
            } else if thinking {
                waiting("Starting…")
            }

            if let problem {
                VStack(alignment: .leading, spacing: 10) {
                    Text(problem)
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if retryable {
                        Button("Try again") { Task { await turn(lastMessage) } }
                            .buttonStyle(SecondaryButtonStyle(height: 44))
                    }
                }
                .padding(12)
                .background(Palette.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task { if !started { await resume() } }
    }

    /// Naming the dependent makes it obvious the policy is already scoped to them.
    private var title: String {
        guard let familyID = session.selectedFamilyID,
              let name = store.dependentName(of: familyID) else { return "Set the policy" }
        return "Set \(name)'s policy"
    }

    // MARK: Pieces

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let progress {
                HStack {
                    Text("\(progress.requiredDone) of \(progress.requiredTotal) settled")
                        .font(Typo.body(13, .medium))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("Turn \(turnsUsed) of \(maxTurns)")
                        .font(Typo.mono(12, .regular))
                        .foregroundStyle(Palette.muted)
                }
                ProgressBar(
                    fraction: progress.requiredTotal == 0
                        ? 0 : Double(progress.requiredDone) / Double(progress.requiredTotal),
                    height: 6
                )
            }
            FlowLayout(spacing: 6) {
                ForEach(checklist) { item in
                    HStack(spacing: 5) {
                        Image(systemName: item.done ? "checkmark" : "circle.dotted")
                            .font(.system(size: 10, weight: .bold))
                        Text(item.label).font(Typo.body(12, .medium))
                    }
                    .foregroundStyle(item.done ? Palette.paper : Palette.muted)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(item.done ? Palette.ink : Palette.graySoft, in: Capsule())
                }
            }
        }
        .cardStyle(padding: 14)
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                SigilMark(size: 24)
                Text(question ?? "…")
                    .font(Typo.body(16))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if thinking {
                waiting("Thinking…")
            } else {
                TextField("Your answer", text: $answer, axis: .vertical)
                    .lineLimit(2...6)
                    .font(Typo.body(16))
                    .focused($answerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 64, alignment: .topLeading)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    )

                Button("Send") { Task { await send() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Start over") { Task { await startOver() } }
                    .buttonStyle(SecondaryButtonStyle(height: 44))
            }
        }
        .cardStyle(radius: 24)
    }

    /// The draft, in base units, with the exact hash the wallet will sign.
    private func ready(_ draft: DraftViewDTO) -> some View {
        let body = PolicyBody(draft.body)

        return VStack(alignment: .leading, spacing: 16) {
            Text("Ready to sign")
                .font(Typo.display(20))
                .tracking(-0.3)
                .accessibilityAddTraits(.isHeader)

            ListCard {
                ValueRow(title: "Weekly cap", value: body.weeklyCap.compact, mono: true)
                ValueRow(title: "Most per request", value: body.maxPerRequest.compact, mono: true)
                ValueRow(title: "Proof needed from", value: body.proofThreshold.compact, mono: true)
                ValueRow(
                    title: "Auditor reviews over",
                    value: body.usesDefaultReviewThreshold
                        ? "\(body.effectiveReviewThreshold.compact) (default)"
                        : body.effectiveReviewThreshold.compact,
                    mono: true
                )
                if let allowance = body.allowance {
                    ValueRow(
                        title: "Allowance",
                        value: "\(allowance.amount.compact) · \(allowance.weekday.label)"
                    )
                } else {
                    ValueRow(title: "Scheduled allowance", value: "None")
                }
                if !body.blockedCategories.isEmpty {
                    ValueRow(
                        title: "Never for",
                        value: body.blockedCategories.map(\.label).joined(separator: ", ")
                    )
                }
            }

            if !draft.testScenarios.isEmpty {
                LabeledSection(title: "What I'd do") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(draft.testScenarios) { scenario in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scenario.scenario)
                                    .font(Typo.body(14, .semibold))
                                Text(scenario.whatIWouldDo)
                                    .font(Typo.body(13))
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineSpacing(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .cardStyle(padding: 14)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("VERSION \(draft.version)")
                    .font(Typo.mono(11)).tracking(0.9).foregroundStyle(Palette.muted)
                Text(draft.bodyHash)
                    .font(Typo.mono(12, .regular))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button {
                Task { await activate(draft) }
            } label: {
                HStack(spacing: 8) {
                    if signing { ProgressView().controlSize(.small).tint(.white) }
                    Text(signing ? "Signing…" : "Sign and activate")
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54))
            .disabled(signing)

            Text("Your wallet signs this exact version and hash. The agent cannot change any of it afterwards.")
                .font(Typo.body(12))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
        }
        .cardStyle(radius: 24)
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Palette.blueInk)
            Text(text).font(Typo.body(14, .medium)).foregroundStyle(Palette.blueInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Talking to the gateway

    /// Picks up an interview that is already under way, rather than asking for an
    /// opening question the gateway will refuse: sending no message is only valid before
    /// the first turn is stored (`422 INTERVIEW_MESSAGE_REQUIRED`).
    private func resume() async {
        thinking = true
        defer { thinking = false }

        let transcript = try? await session.api.interviewTranscript()
        if let transcript, transcript.status == "open", !transcript.turns.isEmpty {
            question = transcript.lastAgentTurn?.text
            turnsUsed = transcript.turns.count
            started = true
            awaitingFirstAnswer = !transcript.turns.contains { $0.role == "guardian" }
            suggestFirstAnswer()
            // An interview that already reached a draft is waiting to be signed.
            if let draftID = transcript.draftPolicyId {
                draft = try? await session.api.draft(id: draftID)
            }
            return
        }
        if let transcript, transcript.status == "completed",
           let draftID = transcript.draftPolicyId {
            draft = try? await session.api.draft(id: draftID)
            started = true
            if draft != nil { return }
        }
        await turn(nil)
    }

    /// Abandons the conversation and asks for a fresh opening question. The gateway keeps
    /// the old turns; nothing was signed, so nothing is lost.
    private func startOver() async {
        try? await session.api.abandonInterview()
        question = nil
        draft = nil
        checklist = []
        progress = nil
        turnsUsed = 0
        started = false
        answer = ""
        suggested = false
        awaitingFirstAnswer = true
        await turn(nil)
    }

    private func send() async {
        let text = answer.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        answer = ""
        answerFocused = false
        suggested = true  // never suggest again once they have answered once
        await turn(text)
    }

    private func turn(_ message: String?) async {
        thinking = true
        problem = nil
        retryable = false
        lastMessage = message
        defer { thinking = false }
        do {
            let result = try await session.api.interview(message: message)
            if result.status == "unavailable" {
                // Nothing was stored, so the same message can simply be sent again.
                problem = "The agent didn't answer. Send that again."
                retryable = true
                return
            }
            withAnimation(.snappy) { apply(result) }
        } catch let error as APIError {
            problem = error.readable
            retryable = error.isRetryable
        } catch {
            problem = "Couldn't reach the gateway."
            retryable = true
        }
    }

    private func apply(_ result: InterviewDTO) {
        question = result.question
        checklist = result.checklist
        progress = result.progress
        turnsUsed = result.turnsUsed
        maxTurns = result.maxTurns
        draft = result.status == "ready" ? result.draft : nil
        started = true
        awaitingFirstAnswer = result.turnsUsed == 0
        suggestFirstAnswer()
    }

    /// Fills the answer box with the part of the opening question the app can already
    /// answer. It is ordinary editable text: change it, or clear it, and what is sent is
    /// whatever is in the box.
    private func suggestFirstAnswer() {
        guard awaitingFirstAnswer, !suggested, answer.isEmpty, draft == nil,
              let familyID = session.selectedFamilyID,
              let name = store.dependentName(of: familyID) else { return }
        suggested = true
        answer = "This is for \(name). "
    }

    private func activate(_ draft: DraftViewDTO) async {
        signing = true
        defer { signing = false }
        if await store.activate(draft: draft) {
            dismiss()
        } else {
            problem = store.problem
            retryable = false
        }
    }
}

#Preview {
    let session = AppSession()
    PolicyInterviewView()
        .environment(session)
        .environment(Store(session: session))
}
