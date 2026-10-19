import SwiftUI

/// Letting the agent spend from the reservoir.
///
/// This is the one place the app builds a real transaction rather than a message to sign:
/// an SPL `ApproveChecked` that delegates aUSD from the guardian's own account to the agent
/// wallet. The money never leaves their wallet — the agent only ever gets permission, which
/// the chain caps and the guardian can take back here at any time.
struct DelegationSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var digits = ""
    @State private var working = false
    @State private var revoking = false
    @State private var result: Store.DelegationResult?
    @FocusState private var amountFocused: Bool

    private var amount: Units { Units(Int64(digits) ?? 0) }

    private var delegated: Units? {
        store.reservoir.map { Units(raw: Int64($0.delegatedAmount)) }
    }

    private var balance: Units? {
        store.reservoir.map { Units(raw: Int64($0.balance)) }
    }

    private var isDelegatedToAgent: Bool {
        store.reservoir?.delegate == Chain.agentWallet
            && (store.reservoir?.delegatedAmount ?? 0) > 0
    }

    private var canApprove: Bool {
        amount > .zero && !working && amount.raw <= (balance?.raw ?? .max)
    }

    var body: some View {
        Screen(spacing: 20) {
            if case .done(let signature) = result {
                success(signature)
            } else {
                header
                current
                amountField
                if let problem = failureText {
                    Text(problem)
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Palette.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                actions
                footnote
            }
        }
        .task { await store.loadReservoir() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isDelegatedToAgent ? "Top up the reservoir" : "Let the agent spend")
                .font(Typo.display(26))
                .tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            Text("Your money stays in your wallet. You are giving the agent permission to spend up to an amount you choose, and you can take it back whenever you like.")
                .font(Typo.body(15))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(3)
        }
    }

    private var current: some View {
        ListCard {
            InfoRow(title: "In your reservoir", value: balance?.display ?? "—")
            InfoRow(title: "The agent may spend", value: delegated?.display ?? "Nothing yet")
            InfoRow(title: "Reservoir", value: short(store.guardianTokenAccount))
        }
    }

    private var amountField: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("$")
                    .font(Typo.mono(36))
                    .foregroundStyle(amount > .zero ? Palette.ink : Palette.dashedChip)
                TextField("0", text: $digits)
                    .font(Typo.mono(48))
                    .tracking(-1.8)
                    .keyboardType(.numberPad)
                    .focused($amountFocused)
                    .fixedSize()
                    .onChange(of: digits) { _, new in
                        // Whole aUSD only, so the approved figure is an exact integer.
                        let cleaned = new.filter(\.isNumber).prefix(7)
                        if cleaned != new { digits = String(cleaned) }
                    }
                    .accessibilityLabel("Amount to approve")
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                ForEach([Int64(100), 250, 500], id: \.self) { quick in
                    Button {
                        withAnimation(.snappy) { digits = String(quick) }
                    } label: {
                        Text("$\(quick)")
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Palette.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { amountFocused = true }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                approve()
            } label: {
                HStack(spacing: 8) {
                    if working, !revoking { ProgressView().controlSize(.small).tint(.white) }
                    Text(working && !revoking ? "Waiting for your wallet…"
                                              : "Approve \(amount > .zero ? amount.compact : "")")
                }
            }
            .buttonStyle(PrimaryButtonStyle(fill: canApprove ? Palette.accent : Palette.dashedChip, height: 54))
            .disabled(!canApprove)

            if isDelegatedToAgent {
                Button {
                    revoke()
                } label: {
                    HStack(spacing: 8) {
                        if working, revoking { ProgressView().controlSize(.small).tint(Palette.danger) }
                        Text("Revoke the agent's permission")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(foreground: Palette.danger, height: 50))
                .disabled(working)
            }

            Button("Cancel") { dismiss() }
                .buttonStyle(SecondaryButtonStyle(height: 50))
                .disabled(working)
        }
    }

    private var footnote: some View {
        VStack(spacing: 6) {
            Text("Approving replaces the current permission rather than adding to it, so enter the new total.")
                .font(Typo.body(12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Text("Signed in your wallet on devnet. Sigil never holds your money.")
                .font(Typo.body(12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func success(_ signature: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.paper)
                    .frame(width: 40, height: 40)
                    .background(Palette.ink, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(revoking ? "Permission taken back" : "The agent can spend \(amount.compact)")
                        .font(Typo.body(16, .bold))
                    Text("Confirmed on devnet")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.muted)
                }
            }

            ListCard {
                InfoRow(title: "In your reservoir", value: balance?.display ?? "—")
                InfoRow(title: "The agent may spend", value: delegated?.display ?? "Nothing")
            }

            if let explorer = Chain.explorer(transaction: signature) {
                Link(destination: explorer) {
                    HStack(spacing: 6) {
                        Text("View on Solana Explorer").font(Typo.body(14, .semibold))
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Palette.accent)
                }
            }

            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle(height: 52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var failureText: String? {
        if case .failed(let message) = result { return message }
        return nil
    }

    private func approve() {
        guard canApprove else { return }
        revoking = false
        act { await store.approveDelegation(amount: amount) }
    }

    private func revoke() {
        revoking = true
        act { await store.revokeDelegation() }
    }

    private func act(_ work: @escaping () async -> Store.DelegationResult) {
        Task {
            working = true
            result = nil
            amountFocused = false
            defer { working = false }
            let outcome = await work()
            // Cancelling in the wallet is an answer, not an error worth shouting about.
            withAnimation(.snappy) { result = outcome == .cancelled ? nil : outcome }
        }
    }

    private func short(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(4))…\(address.suffix(4))"
    }
}

#Preview {
    let session = AppSession()
    Color.white.sheet(isPresented: .constant(true)) {
        DelegationSheet().environment(Store(session: session))
    }
}
