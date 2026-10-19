import SwiftUI
import Observation

/// The one request the dependent is currently waiting on.
///
/// The gateway's agent run is synchronous and can take up to 150 s, so a request
/// genuinely sits in a waiting state and must be visible while it does. Until the
/// API layer exists, `settle()` stands in for the agent by applying the documented
/// order of checks to the policy the app already holds.
@Observable
final class LiveRequest: Identifiable {
    let id = UUID()
    let amount: Units
    let category: Category
    let note: String
    let emergency: Bool
    let dependentID: String

    /// Nil while the agent is still running.
    var outcome: Outcome?
    var reply = ""
    var amountSent = Units.zero
    /// Set when the stand-in agent asks something back, so the card can show it.
    var question: String?

    init(amount: Units, category: Category, note: String, emergency: Bool, dependentID: String) {
        self.amount = amount
        self.category = category
        self.note = note
        self.emergency = emergency
        self.dependentID = dependentID
    }

    var title: String {
        note.isEmpty ? category.label : note
    }

    private var policy: PolicyBody { MockData.policy(for: dependentID).body }
    private var budget: Budget { MockData.budget(for: dependentID) }
    private var guardianName: String { MockData.guardian.shortName }

    /// Where the owed receipt has got to. The gateway lifts the block only once it has
    /// accepted the proof, and it refuses an unsigned PDF outright, so sending one is not
    /// the end of the story.
    enum ReceiptState: Equatable {
        case notNeeded
        case owed
        case checking
        case refused(String)
        case accepted
    }

    var receipt: ReceiptState = .notNeeded

    /// True while money is out and the receipt has not been accepted.
    var owesReceipt: Bool {
        switch receipt {
        case .notNeeded, .accepted: false
        case .owed, .checking, .refused: true
        }
    }

    /// Mirrors the documented decision order closely enough to exercise every
    /// affordance from the simulator. The real answer comes from the agent.
    func settle() {
        if policy.blockedCategories.contains(category) {
            outcome = .blocked
            reply = "I can't send this one — \(category.label.lowercased()) is blocked in your policy. Ask \(guardianName) if you'd like that changed."
        } else if emergency {
            outcome = .askedGuardian
            reply = "I've asked \(guardianName) straight away and sent her my recommendation. You'll get a notification as soon as she decides."
        } else if amount > policy.maxPerRequest {
            outcome = .askedGuardian
            reply = "That's over your \(policy.maxPerRequest.compact) per-request limit, so only \(guardianName) can approve it. I've asked her and recommended it."
        } else if amount > budget.remaining {
            outcome = .counterOffer
            amountSent = budget.remaining
            reply = "You have \(budget.remaining.compact) left this week. I can send that now, or the full \(amount.compact) once your budget resets on Monday."
        } else if amount >= policy.proofThreshold {
            // Over the threshold the money goes out first — you can't buy anything
            // before you're paid — and the receipt is owed afterwards.
            outcome = .sentFull
            amountSent = amount
            receipt = .owed
            reply = "Sent — \(amount.compact) for \(category.label.lowercased()). Anything over \(policy.proofThreshold.compact) needs a receipt afterwards, so send me one once you've paid. I can't send anything more until you do."
        } else {
            outcome = .sentFull
            amountSent = amount
            reply = "Sent — \(amount.compact) for \(category.label.lowercased()). That's well inside your limits this week."
        }
    }

    func acceptCounterOffer() {
        outcome = .sentPartial
        reply = "Sent \(amountSent.compact). Ask me again after Monday if you still need the rest."
    }

    func escalateToGuardian() {
        outcome = .askedGuardian
        amountSent = .zero
        reply = "I've asked \(guardianName), with what you told me and my own view. You'll get a notification when she answers."
    }

    /// Sends the owed receipt off to be checked. Nothing here decides the outcome: the
    /// gateway verifies the capture or the shop's signature on the PDF and only then lifts
    /// the block, so the app shows it being checked and reports what came back.
    func sendReceipt(from source: ProofSource) async {
        receipt = .checking
        try? await Task.sleep(for: .milliseconds(1_200))

        // An unsigned PDF is refused outright, so the dependent is told rather than left
        // waiting. `-refuseProof` forces that path for checking it on the simulator.
        let refuse = source == .document
            && ProcessInfo.processInfo.arguments.contains("-refuseProof")
        if refuse {
            receipt = .refused(
                "That PDF isn't signed by the shop, so I can't use it. Ask them for the signed copy, or photograph a paper receipt."
            )
            return
        }
        receipt = .accepted
        let what = source == .camera ? "receipt" : "order confirmation"
        reply = "Thanks — that \(what) covers \(amount.compact). You're clear to ask for money again."
    }
}

/// The live request as a card. Every move the agent can make is a tap, never typing.
struct LiveRequestCard: View {
    @Bindable var request: LiveRequest
    var onDone: () -> Void

    private var guardianName: String { MockData.guardian.shortName }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.title.capitalizedFirst)
                        .font(Typo.body(15, .semibold))
                    Text(request.amount.display)
                        .font(Typo.mono(24))
                        .tracking(-0.6)
                }
                Spacer()
                if let outcome = request.outcome {
                    StatusBadge(outcome: outcome, guardianName: guardianName)
                } else {
                    waitingBadge
                }
            }

            if let outcome = request.outcome {
                HStack(alignment: .top, spacing: 10) {
                    SigilMark(size: 22)
                    Text(request.reply)
                        .font(Typo.body(14))
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                actions(for: outcome)
            } else {
                Text("Checking this against your policy. This can take a minute.")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.muted)
            }
        }
        .cardStyle(radius: 24)
    }

    private var checkingReceipt: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Palette.blueInk)
            Text("Checking your receipt…")
                .font(Typo.body(14, .medium))
                .foregroundStyle(Palette.blueInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// A refused receipt leaves the money still owed, so the reason comes with another go.
    private func refusedReceipt(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.orangeInk)
                Text(reason)
                    .font(Typo.body(14))
                    .foregroundStyle(Palette.orangeInk)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.orangeSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            receiptActions
        }
    }

    /// Two ways to send a receipt: the app's camera for a paper one, or the PDF for an
    /// online order. No gallery picker, and screenshots are not accepted.
    private var receiptActions: some View {
        VStack(spacing: 10) {
            ForEach(ProofSource.allCases) { source in
                Button {
                    Task { await request.sendReceipt(from: source) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: source.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(source.title).font(Typo.body(15, .semibold))
                            Text(source.detail)
                                .font(Typo.body(12))
                                .foregroundStyle(source == .camera ? .white.opacity(0.75) : Palette.muted)
                        }
                        Spacer()
                    }
                    .foregroundStyle(source == .camera ? .white : Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .background(
                        source == .camera ? Palette.accent : Palette.card,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        if source == .document {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.borderStrong, lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var waitingBadge: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini).tint(Palette.blueInk)
            Text("Asking").font(Typo.body(12, .semibold))
        }
        .foregroundStyle(Palette.blueInk)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Palette.blueSoft, in: Capsule())
    }

    @ViewBuilder
    private func actions(for outcome: Outcome) -> some View {
        switch outcome {
        case .counterOffer:
            HStack(spacing: 10) {
                Button("Ask \(guardianName)") {
                    withAnimation(.snappy) { request.escalateToGuardian() }
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Take \(request.amountSent.compact)") {
                    withAnimation(.snappy) { request.acceptCounterOffer() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }

        case .askedProof:
            receiptActions

        case .blocked, .declined:
            HStack(spacing: 10) {
                Button("Close", action: onDone)
                    .buttonStyle(SecondaryButtonStyle())
                Button("Ask \(guardianName) anyway") {
                    withAnimation(.snappy) { request.escalateToGuardian() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }

        case .sentFull, .sentPartial:
            switch request.receipt {
            case .owed:
                receiptActions
            case .checking:
                checkingReceipt
            case .refused(let reason):
                refusedReceipt(reason)
            case .notNeeded, .accepted:
                Button("Done", action: onDone)
                    .buttonStyle(SecondaryButtonStyle())
            }

        default:
            // asked_guardian and anything new from the gateway: nothing to tap,
            // and transfer_pending must never offer a retry.
            Button("Close", action: onDone)
                .buttonStyle(SecondaryButtonStyle())
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        isEmpty ? self : prefix(1).uppercased() + dropFirst()
    }
}

#Preview {
    let request = LiveRequest(amount: Units(65), category: .clothing, note: "winter jacket",
                              emergency: false, dependentID: "mt")
    request.settle()

    return VStack(spacing: 16) {
        LiveRequestCard(request: request) {}
        LiveRequestCard(request: LiveRequest(amount: Units(25), category: .food, note: "",
                                             emergency: false, dependentID: "mt")) {}
    }
    .padding()
    .background(Palette.paper)
}
