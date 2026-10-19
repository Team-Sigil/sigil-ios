import SwiftUI
import Observation

/// The one request the dependent is currently waiting on.
///
/// The gateway runs the agent while the call is open and allows it up to 150 s, so a
/// request genuinely sits in a waiting state and must be visible while it does. Every
/// outcome here comes from the agent: nothing about the decision is worked out in the app.
@MainActor
@Observable
final class LiveRequest: Identifiable {
    let id = UUID()
    let amount: Units
    let category: Category
    let note: String
    let emergency: Bool
    let familyID: String

    /// The gateway's request, once it has been created.
    private(set) var requestID: String?

    /// Nil while the agent is still running.
    var outcome: Outcome?
    var reply = ""
    var amountSent = Units.zero
    /// Set when something went wrong rather than when the agent decided something.
    var problem: String?

    private let store: Store

    init(
        amount: Units,
        category: Category,
        note: String,
        emergency: Bool,
        familyID: String,
        store: Store
    ) {
        self.amount = amount
        self.category = category
        self.note = note
        self.emergency = emergency
        self.familyID = familyID
        self.store = store
    }

    var title: String {
        note.isEmpty ? category.label : note
    }

    private var guardianName: String { store.guardianName }

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

    // MARK: Talking to the gateway

    /// Creates the request and waits for the agent's answer.
    func send() async {
        let answer = await store.ask(
            amount: amount, category: category, purpose: note, emergency: emergency
        )
        guard let answer else {
            problem = store.problem
            outcome = .safeFallback
            reply = store.problem ?? "That didn't go through."
            return
        }
        requestID = answer.request
        apply(answer.decision)
    }

    /// Taking a smaller offer, or sending it to the guardian, is a follow-up on the same
    /// request: the agent decides again with the new message in the thread.
    func acceptCounterOffer() async {
        await follow(up: "Yes — send me the \(amountSent.compact) now, please.")
    }

    func escalateToGuardian() async {
        await follow(up: "Please ask \(guardianName) about this one.")
    }

    private func follow(up message: String) async {
        let previous = outcome
        outcome = nil
        guard let requestID, let decision = await store.follow(up: requestID, message: message)
        else {
            outcome = previous
            problem = store.problem
            return
        }
        apply(decision)
    }

    private func apply(_ decision: Decision) {
        // A receipt check is not a new decision about the request (gateway app handoff,
        // "Proof after payment"): the money already went out, so the outcome and the amount
        // stand and only the receipt's own state and the agent's words move. Letting
        // `receipt_accepted` become the outcome would wipe "Sent $65" off a card that did.
        if !decision.outcome.isReceiptCheck {
            outcome = decision.outcome
            amountSent = decision.amountSent
        }
        reply = decision.replyToDependent
        // A receipt is owed for money already sent. Up to three may be owed at once; the
        // gateway only refuses the next request at three (gateway app handoff, "Proof
        // after payment").
        if let requestID, store.owesReceipt(request: requestID) {
            if receipt == .notNeeded { receipt = .owed }
        } else if receipt == .owed {
            receipt = .accepted
        }
    }

    /// Sends the owed receipt off to be checked. Nothing here decides the outcome: the
    /// gateway verifies the capture or the shop's signature on the PDF and only then lifts
    /// the block, so the app shows it being checked and reports what came back.
    func upload(_ data: Data, filename: String, mediaType: String, verified: Bool) async {
        guard let requestID else { return }
        receipt = .checking
        let result = await store.sendProof(
            requestID: requestID, data: data, filename: filename,
            mediaType: mediaType, verified: verified
        )
        switch result {
        case .accepted(let decision):
            receipt = .accepted
            if let decision { apply(decision) }
        case .notEvidence(let reason):
            receipt = .refused(reason)
        case .rejected(let reason, let decision):
            receipt = .refused(reason)
            if let decision { apply(decision) }
        case .stillOwed(let decision):
            receipt = .owed
            if let decision { apply(decision) }
        case .failed(let reason):
            receipt = .refused(reason)
        }
    }
}

/// The live request as a card. Every move the agent can make is a tap, never typing.
struct LiveRequestCard: View {
    @Bindable var request: LiveRequest
    var onDone: () -> Void

    @Environment(Store.self) private var store
    @State private var takingPhoto = false
    @State private var pickingDocument = false
    @State private var cameraProblem: String?

    private var guardianName: String { store.guardianName }

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
        .sheet(isPresented: $takingPhoto) {
            CameraSheet { data in
                Task { await request.upload(
                    data, filename: "receipt.jpg", mediaType: "image/jpeg", verified: true
                ) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $pickingDocument) {
            DocumentSheet { data, name in
                Task { await request.upload(
                    data, filename: name, mediaType: "application/pdf", verified: false
                ) }
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
            if let cameraProblem {
                Text(cameraProblem)
                    .font(Typo.body(12))
                    .foregroundStyle(Palette.orangeInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(ProofSource.allCases) { source in
                Button {
                    open(source)
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

    /// The camera is the app's own, with no gallery picker; an online order comes in as
    /// the shop's PDF instead.
    private func open(_ source: ProofSource) {
        cameraProblem = nil
        switch source {
        case .camera:
            guard CameraSheet.isAvailable else {
                cameraProblem = "This device has no camera, so send the shop's PDF instead."
                return
            }
            takingPhoto = true
        case .document:
            pickingDocument = true
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
                    Task { await request.escalateToGuardian() }
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Take \(request.amountSent.compact)") {
                    Task { await request.acceptCounterOffer() }
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
                    Task { await request.escalateToGuardian() }
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
    let session = AppSession()
    let store = Store(session: session)
    let request = LiveRequest(amount: Units(65), category: .clothing, note: "winter jacket",
                              emergency: false, familyID: "", store: store)
    request.outcome = .sentFull
    request.amountSent = Units(65)
    request.receipt = .owed
    request.reply = "Sent — $65 for clothing. Send me the receipt once you have paid."

    return VStack(spacing: 16) {
        LiveRequestCard(request: request) {}
        LiveRequestCard(request: LiveRequest(amount: Units(25), category: .food, note: "",
                                             emergency: false, familyID: "", store: store)) {}
    }
    .padding()
    .background(Palette.paper)
    .environment(store)
}
