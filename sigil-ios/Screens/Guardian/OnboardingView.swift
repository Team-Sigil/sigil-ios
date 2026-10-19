import SwiftUI
import UIKit

/// A guardian with no dependents yet.
///
/// Registering one is a signed act: the guardian's wallet signs the dependent's wallet and
/// token account, and that signature is what makes the account the only place money can
/// ever go (SEC-01). Every dependent of a guardian shares one reservoir, so the token
/// account comes from the families that already exist.
struct OnboardingView: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var wallet = ""
    @State private var working = false
    @State private var scanning = false
    @State private var destination: String?
    @State private var accountState = AccountState.idle
    @State private var checking: Task<Void, Never>?
    /// Set only when the guardian has been told the account is missing and chose to go on
    /// anyway. Payments to that dependent will fail at the signer until it exists.
    @State private var registerRegardless = false

    /// What devnet says about the dependent's aUSD account. The gateway doesn't check it,
    /// and registering an account that doesn't exist means every payment fails later.
    private enum AccountState: Equatable {
        case idle
        /// Typed, but not a Solana address.
        case notAnAddress
        case checking
        case exists
        case missing
        case unknown
    }

    private var cleanWallet: String {
        wallet.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var reservoir: String { store.guardianTokenAccount }

    private var canRegister: Bool {
        guard destination != nil, !working else { return false }
        return accountState == .exists || registerRegardless
    }

    var body: some View {
        Screen(spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.families.isEmpty ? "Add your first dependent" : "Add a dependent")
                    .font(Typo.display(28))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text("They sign in with their own wallet. You sign who they are, and that signature is what keeps the money going only to them.")
                    .font(Typo.body(15))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
            }

            LabeledSection(title: "Who") {
                VStack(spacing: 12) {
                    field("Their name", text: $name, placeholder: "Min Thu")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Their wallet address")
                            .font(Typo.body(13, .medium))
                            .foregroundStyle(Palette.textSecondary)
                        HStack(spacing: 8) {
                            TextField("9Hq4…2mFe", text: $wallet)
                                .font(Typo.mono(15, .regular))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Palette.borderStrong, lineWidth: 1)
                                )
                            Button { paste() } label: {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                    .frame(width: 50, height: 50)
                                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Palette.borderStrong, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Paste their wallet address")

                            Button { scanning = true } label: {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(Palette.paper)
                                    .frame(width: 50, height: 50)
                                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Scan their wallet QR code")
                        }
                        Text("Scan the QR on their wallet's Receive screen, or paste the address.")
                            .font(Typo.body(12))
                            .foregroundStyle(Palette.muted)
                    }
                }
                accountStatus
            }

            LabeledSection(title: "Paid from (shared)") {
                HStack(spacing: 12) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.paper)
                        .frame(width: 44, height: 30)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.families.isEmpty ? "Your reservoir" : "Your existing reservoir")
                            .font(Typo.body(15, .semibold))
                        Text(reservoir.isEmpty ? "Connect your wallet first" : reservoir)
                            .font(Typo.mono(12, .regular))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .padding(.vertical, -2)
                .cardStyle(padding: 14)

                Text("Every dependent you add spends from this one account, so top it up to cover them all.")
                    .font(Typo.body(12))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)
            }

            if let problem = store.problem {
                Text(problem)
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Palette.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                register()
            } label: {
                HStack(spacing: 8) {
                    if working { ProgressView().controlSize(.small).tint(.white) }
                    Text(working ? "Waiting for your wallet…" : "Sign and add")
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54))
            .disabled(!canRegister)
            .opacity(canRegister ? 1 : 0.5)

            Text("Your wallet signs their wallet and account. The agent can never send anywhere else.")
                .font(Typo.body(12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if store.families.isEmpty {
                SignOutButton { session.signOut() }
            }
        }
        .sheet(isPresented: $scanning) {
            QRScannerSheet { address in
                wallet = address
            }
        }
        .onChange(of: wallet) { _, _ in resolve() }
        .task { store.problem = nil }
    }

    /// What is known about the address typed or scanned so far: whether it is an address
    /// at all, which account their money would land in, and whether that account is real.
    @ViewBuilder private var accountStatus: some View {
        switch accountState {
        case .idle:
            EmptyView()
        case .notAnAddress:
            status(icon: "questionmark.circle", tint: Palette.muted,
                   title: "That isn't a Solana wallet address",
                   detail: "It should be about 44 letters and numbers.")
        case .checking:
            status(icon: "ellipsis", tint: Palette.muted,
                   title: "Looking up their aUSD account…", detail: destination)
        case .exists:
            status(icon: "checkmark.seal.fill", tint: Palette.green,
                   title: "Their aUSD account is ready", detail: destination)
        case .missing:
            VStack(alignment: .leading, spacing: 10) {
                status(icon: "exclamationmark.triangle.fill", tint: Palette.orangeInk,
                       title: "This wallet has no aUSD account yet",
                       detail: "They need to hold aUSD on devnet before money can reach them.")
                if registerRegardless {
                    Text("Adding them anyway. Payments will fail until the account exists.")
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.orangeInk)
                        .padding(.horizontal, 4)
                } else {
                    Button("Add them anyway") {
                        withAnimation(.snappy) { registerRegardless = true }
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 44))
                }
            }
        case .unknown:
            status(icon: "wifi.exclamationmark", tint: Palette.orangeInk,
                   title: "Couldn't reach devnet to check their account",
                   detail: "Try again in a moment.")
        }
    }

    private func status(icon: String, tint: Color, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.body(13, .semibold))
                if let detail {
                    Text(detail)
                        .font(Typo.mono(11, .regular))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Works out their token account from the address and asks devnet whether it exists.
    /// The account is derived, never typed: it is the aUSD account of that wallet.
    private func resolve() {
        checking?.cancel()
        destination = nil
        registerRegardless = false
        guard !cleanWallet.isEmpty else {
            accountState = .idle
            return
        }
        guard Base58.isPubkey(cleanWallet), let account = TokenAccount.of(wallet: cleanWallet)
        else {
            accountState = .notAnAddress
            return
        }
        destination = account
        accountState = .checking
        checking = Task {
            // A moment's pause, so typing doesn't fire a request per keystroke.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let exists = await Devnet.accountExists(account)
            guard !Task.isCancelled else { return }
            accountState = switch exists {
            case true: .exists
            case false: .missing
            default: .unknown
            }
        }
    }

    private func paste() {
        guard let text = UIPasteboard.general.string else { return }
        // Whatever was copied may carry a scheme or spaces around it.
        wallet = QRScannerSheet.address(in: text) ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func register() {
        guard canRegister, let destination else { return }
        Task {
            working = true
            defer { working = false }
            let added = await store.registerDependent(
                wallet: cleanWallet,
                tokenAccount: destination,
                guardianTokenAccount: reservoir,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if added {
                wallet = ""
                name = ""
                accountState = .idle
                // Presented as a sheet when adding a second dependent; closing it is how
                // the guardian sees the one they just added. Harmless at the root, where
                // the app moves on by itself once a family exists.
                dismiss()
            }
        }
    }

    private func field(
        _ label: String, text: Binding<String>, placeholder: String, mono: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Typo.body(13, .medium))
                .foregroundStyle(Palette.textSecondary)
            TextField(placeholder, text: text)
                .font(mono ? Typo.mono(15, .regular) : Typo.body(16))
                .textInputAutocapitalization(mono ? .never : .words)
                .autocorrectionDisabled(mono)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.borderStrong, lineWidth: 1)
                )
        }
    }
}

#Preview {
    let session = AppSession()
    OnboardingView()
        .environment(session)
        .environment(Store(session: session))
}
