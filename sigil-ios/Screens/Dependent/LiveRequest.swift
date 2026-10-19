import Observation
import SwiftUI

/// The request the dependent is currently waiting on.
///
/// The agent decides, not the app: this only holds what was asked and what came back. The
/// gateway's run is synchronous and can take up to 150 s, so a request genuinely sits in a
/// waiting state and has to be visible while it does.
@Observable
final class LiveRequest: Identifiable {
    let id = UUID()
    let amount: Units
    let category: Category
    let note: String
    let emergency: Bool
    /// Only used to know whether a receipt will be owed once the money goes out.
    private let proofThreshold: Units

    /// Nil while the agent is still running.
    var outcome: Outcome?
    /// The agent's own words, which the gateway says to show rather than our own.
    var reply = ""
    var amountSent = Units.zero

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

    var owesReceipt: Bool {
        switch receipt {
        case .notNeeded, .accepted: false
        case .owed, .checking, .refused: true
        }
    }

    init(
        amount: Units, category: Category, note: String, emergency: Bool, proofThreshold: Units
    ) {
        self.amount = amount
        self.category = category
        self.note = note
        self.emergency = emergency
        self.proofThreshold = proofThreshold
    }

    var title: String {
        note.isEmpty ? category.label : note
    }

    /// Takes whatever the agent answered. Over the proof threshold the money goes out
    /// first — you cannot buy anything before you are paid — and the receipt is owed.
    func settle(with decision: Decision) {
        outcome = decision.outcome
        reply = decision.replyToDependent
        amountSent = decision.amountSent
        if decision.outcome.isMoneyMoving, proofThreshold > .zero,
           decision.amountSent >= proofThreshold {
            receipt = .owed
        }
    }

    /// Sends the owed receipt off to be checked. Nothing here decides the outcome: the
    /// gateway verifies the capture or the shop's signature on the PDF and only then lifts
    /// the block, so the app shows it being checked and reports what came back.
    func sendReceipt(from source: ProofSource) async {
        receipt = .checking
        try? await Task.sleep(for: .milliseconds(1_200))

        // Uploading is not built yet: the camera needs App Attest and the PDF needs a file
        // picker. `-refuseProof` shows the refusal path, which an unsigned PDF really gets.
        if ProcessInfo.processInfo.arguments.contains("-refuseProof"), source == .document {
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
    var guardianName: String
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.title.capitalizedFirstLetter)
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
        switch request.receipt {
        case .owed:
            receiptActions
        case .checking:
            checkingReceipt
        case .refused(let reason):
            refusedReceipt(reason)
        case .notNeeded, .accepted:
            if outcome == .askedProof {
                receiptActions
            } else {
                Button("Done", action: onDone)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
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
}
