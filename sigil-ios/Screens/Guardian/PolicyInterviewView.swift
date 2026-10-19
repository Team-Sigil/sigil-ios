import SwiftUI

/// Setting the policy by talking to the agent.
///
/// The guardian answers questions in their own words; the gateway stores every turn and
/// the agent drafts the limits. The app can only ever send the guardian's own message —
/// there is no way to submit an agent turn — so the "ready" state that the signing step
/// depends on cannot be faked from here. Nothing takes effect until the guardian signs the
/// draft's hash.
struct PolicyInterviewView: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var interview: InterviewDTO?
    @State private var answer = ""
    @State private var thinking = false
    @State private var problem: String?
    @State private var signing = false
    @FocusState private var answerFocused: Bool

    var body: some View {
        Screen(spacing: 20) {
            PageTitle(title: "Set the policy",
                      subtitle: "Answer in your own words. Nothing is live until you sign it.")

            if let interview {
                checklist(interview)

                if let draft = interview.draft, interview.status == "ready" {
                    ready(draft)
                } else {
                    question(interview)
                }
            } else if thinking {
                waiting("Starting…")
            }

            if let problem {
                Text(problem)
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Palette.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task { if interview == nil { await start() } }
    }

    // MARK: Pieces

    private func checklist(_ interview: InterviewDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let progress = interview.progress {
                HStack {
                    Text("\(progress.requiredDone) of \(progress.requiredTotal) settled")
                        .font(Typo.body(13, .medium))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("Turn \(interview.turnsUsed) of \(interview.maxTurns)")
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
                ForEach(interview.checklist) { item in
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

    private func question(_ interview: InterviewDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                SigilMark(size: 24)
                Text(interview.question ?? "…")
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
            }
        }
        .cardStyle(radius: 24)
    }

    /// The draft, in base units, with the hash the wallet will sign.
    private func ready(_ draft: DraftViewDTO) -> some View {
        let body = PolicyBody(draft.body)

        return VStack(alignment: .leading, spacing: 16) {
            Text("Ready to sign")
                .font(Typo.display(20))
                .tracking(-0.3)

            ListCard {
                ValueRow(title: "Weekly cap", value: body.weeklyCap.compact, mono: true)
                ValueRow(title: "Most per request", value: body.maxPerRequest.compact, mono: true)
                ValueRow(title: "Proof needed over", value: body.proofThreshold.compact, mono: true)
                if let allowance = body.allowance {
                    ValueRow(
                        title: "Allowance",
                        value: "\(allowance.amount.compact) · \(allowance.weekday.label)"
                    )
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
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(draft.testScenarios, id: \.self) { scenario in
                            HStack(alignment: .top, spacing: 8) {
                                Text("·").font(Typo.body(14, .bold))
                                Text(scenario)
                                    .font(Typo.body(14))
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineSpacing(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private func start() async { await turn(nil) }

    private func send() async {
        let text = answer.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        answer = ""
        answerFocused = false
        await turn(text)
    }

    private func turn(_ message: String?) async {
        thinking = true
        problem = nil
        defer { thinking = false }
        do {
            let result = try await session.api.interview(message: message)
            if result.status == "unavailable" {
                // Nothing was stored, so the same message can simply be sent again.
                problem = "The agent didn't answer. Try sending that again."
                return
            }
            withAnimation(.snappy) { interview = result }
        } catch let error as APIError {
            problem = error.readable
        } catch {
            problem = "Couldn't reach the gateway."
        }
    }

    private func activate(_ draft: DraftViewDTO) async {
        signing = true
        problem = nil
        defer { signing = false }
        do {
            let api = session.api
            let address = try session.signer.address
            let nonce = try await api.nonce(wallet: address, purpose: "activate-policy").nonce
            let text = SignedMessage.activatePolicy(
                family: session.selectedFamilyID ?? "",
                version: draft.version,
                hash: draft.bodyHash,
                nonce: nonce
            )
            _ = try await api.activateDraft(
                id: draft.id, nonce: nonce, signature: try session.signer.sign(text)
            )
            await store.load()
            dismiss()
        } catch let error as APIError {
            problem = error.readable
        } catch {
            problem = "Couldn't reach the gateway."
        }
    }
}
