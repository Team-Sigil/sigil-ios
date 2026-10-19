import SwiftUI

/// The receipts owed for money already sent, as a list of jobs to finish.
///
/// Money at or above the proof threshold goes out first and the receipt follows, so an
/// owed receipt is not a warning about something that went wrong — it is a task, for money
/// the dependent already has. Up to three may be owed at once; only at three does the
/// gateway refuse the next request (`409 PROOF_OUTSTANDING`). So this reads as a checklist
/// that happens to have a ceiling, and only says the ceiling has been hit once it has.
struct OwedReceiptsCard: View {
    @Environment(Store.self) private var store

    /// The obligation whose receipt is being sent, if any.
    @State private var sending: ProofObligation?
    /// Where an upload for a given obligation has got to, keyed by obligation id.
    @State private var progress: [String: Progress] = [:]

    private enum Progress: Equatable {
        case checking
        case accepted
        case refused(String)
    }

    private var owed: [ProofObligation] { store.owedReceipts }

    var body: some View {
        if !owed.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                header
                VStack(spacing: 0) {
                    ForEach(Array(owed.enumerated()), id: \.element.id) { index, obligation in
                        if index > 0 {
                            Rectangle().fill(Palette.border).frame(height: 1)
                        }
                        row(obligation)
                    }
                }
                footnote
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .sheet(item: $sending) { obligation in
                SendReceiptSheet(obligation: obligation) { data, filename, mediaType, verified in
                    upload(obligation, data: data, filename: filename,
                           mediaType: mediaType, verified: verified)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.paper, in: Circle())
                .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(owed.count == 1 ? "1 receipt to send" : "\(owed.count) receipts to send")
                    .font(Typo.body(16, .bold))
                    .accessibilityAddTraits(.isHeader)
                Text("For money already in your account")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Text("\(owed.count)/\(Store.maxOwedReceipts)")
                .font(Typo.mono(13, .semibold))
                .foregroundStyle(store.owedReceiptsAreBlocking ? Palette.orangeInk : Palette.muted)
        }
    }

    private func row(_ obligation: ProofObligation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state(obligation) == .accepted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(state(obligation) == .accepted ? Palette.green : Palette.dashedChip)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(obligation.amount.compact) · \(obligation.title)")
                    .font(Typo.body(14, .semibold))
                    .lineLimit(1)
                switch state(obligation) {
                case .checking:
                    Text("Checking your receipt…")
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.blueInk)
                case .accepted:
                    Text("Accepted")
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.green)
                case .refused(let reason):
                    Text(reason)
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.orangeInk)
                        .lineSpacing(1)
                case nil:
                    Text("Sent \(obligation.sentAgo)")
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state(obligation) == .checking {
                ProgressView().controlSize(.small).tint(Palette.blueInk)
            } else {
                Button(isRefused(obligation) ? "Try again" : "Send") { sending = obligation }
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var footnote: some View {
        if store.owedReceiptsAreBlocking {
            Text("That is as many as you can owe at once. Send one of these and you can ask for money again.")
                .font(Typo.body(12))
                .foregroundStyle(Palette.orangeInk)
                .lineSpacing(2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.orangeSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Text("You can still ask for money. At \(Store.maxOwedReceipts) owed receipts you have to send one first.")
                .font(Typo.body(12))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
        }
    }

    private func state(_ obligation: ProofObligation) -> Progress? {
        progress[obligation.id]
    }

    private func isRefused(_ obligation: ProofObligation) -> Bool {
        if case .refused = state(obligation) { return true }
        return false
    }

    /// The gateway decides: it verifies the capture or the shop's signature, reads the
    /// receipt and settles the obligation or refuses the proof. The app only reports back.
    private func upload(
        _ obligation: ProofObligation,
        data: Data, filename: String, mediaType: String, verified: Bool
    ) {
        Task {
            progress[obligation.id] = .checking
            let result = await store.sendProof(
                requestID: obligation.requestID, data: data, filename: filename,
                mediaType: mediaType, verified: verified
            )
            switch result {
            case .accepted:
                // `sendProof` reloads, so an accepted receipt is already gone from the
                // list. The tick is for the moment before that lands.
                progress[obligation.id] = .accepted
            case .rejected(let reason, _):
                progress[obligation.id] = .refused(reason)
            case .notEvidence(let reason), .failed(let reason):
                progress[obligation.id] = .refused(reason)
            case .stillOwed(let decision):
                // The agent's own words say why: it wants a clearer photo, it couldn't check
                // just now, and so on. A fixed line here hid every one of those behind the
                // same message.
                let reply = decision?.replyToDependent
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                progress[obligation.id] = .refused(
                    reply.isEmpty
                        ? "That didn't settle the receipt. Send a clear photo of it, or the shop's PDF."
                        : reply
                )
            }
        }
    }
}

/// Picks how one owed receipt is sent: the app's own camera for a paper one, or the shop's
/// PDF for an online order. There is no gallery picker, and a screenshot is not accepted.
private struct SendReceiptSheet: View {
    let obligation: ProofObligation
    let onPicked: (Data, String, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var takingPhoto = false
    @State private var pickingDocument = false
    @State private var cameraProblem: String?

    var body: some View {
        Screen(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Send the receipt")
                    .font(Typo.display(26))
                    .tracking(-0.5)
                    .accessibilityAddTraits(.isHeader)
                Text("For the \(obligation.amount.display) sent \(obligation.sentAgo) — \(obligation.title).")
                    .font(Typo.body(15))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
            }

            if let cameraProblem {
                Text(cameraProblem)
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.orangeInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Palette.orangeSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(spacing: 10) {
                ForEach(ProofSource.allCases) { source in
                    Button { open(source) } label: {
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

            Button("Not now") { dismiss() }
                .buttonStyle(SecondaryButtonStyle(height: 50))
        }
        .sheet(isPresented: $takingPhoto) {
            CameraSheet { data in
                onPicked(data, "receipt.jpg", "image/jpeg", true)
                dismiss()
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $pickingDocument) {
            DocumentSheet { data, name in
                onPicked(data, name, "application/pdf", false)
                dismiss()
            }
        }
    }

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
}
