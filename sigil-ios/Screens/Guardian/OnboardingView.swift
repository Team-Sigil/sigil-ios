import SwiftUI

/// A guardian with no dependents yet.
///
/// Registering one is a signed act: the guardian's wallet signs the dependent's wallet and
/// token account, and that signature is what makes the account the only place money can
/// ever go. Every dependent of a guardian shares one reservoir, so the token account is
/// taken from the families that already exist.
struct OnboardingView: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store

    @State private var name = ""
    @State private var wallet = ""
    @State private var tokenAccount = ""
    @State private var reservoir = ""
    @State private var working = false

    private var existingReservoir: String? {
        store.families.first?.guardianTokenAccount
    }

    private var canRegister: Bool {
        !wallet.isEmpty && !tokenAccount.isEmpty
            && !(existingReservoir == nil && reservoir.isEmpty) && !working
    }

    var body: some View {
        Screen(spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add your first dependent")
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
                    field("Their wallet address", text: $wallet, placeholder: "9Hq4…2mFe", mono: true)
                    field("Their token account", text: $tokenAccount, placeholder: "5Tc9…vB3n", mono: true)
                }
            }

            LabeledSection(title: "Paid from") {
                if let existingReservoir {
                    HStack(spacing: 12) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.paper)
                            .frame(width: 44, height: 30)
                            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your existing reservoir").font(Typo.body(15, .semibold))
                            Text(existingReservoir)
                                .font(Typo.mono(12, .regular))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .padding(.vertical, -2)
                    .cardStyle(padding: 14)
                } else {
                    field("Your token account", text: $reservoir, placeholder: "6Jn2…qW4r", mono: true)
                    Text("All your dependents spend from this one account, so the same one is used every time you add someone.")
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(2)
                        .padding(.horizontal, 4)
                }
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
                Task {
                    working = true
                    defer { working = false }
                    _ = await store.registerDependent(
                        wallet: wallet.trimmingCharacters(in: .whitespaces),
                        tokenAccount: tokenAccount.trimmingCharacters(in: .whitespaces),
                        guardianTokenAccount: existingReservoir
                            ?? reservoir.trimmingCharacters(in: .whitespaces),
                        name: name
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    if working { ProgressView().controlSize(.small).tint(.white) }
                    Text(working ? "Signing…" : "Sign and add")
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54))
            .disabled(!canRegister)
            .opacity(canRegister ? 1 : 0.5)
        }
        .task { await registerDemoDependentIfAsked() }
    }

    /// `-demoDependent` registers a throwaway dependent so the guardian screens can be
    /// checked on the simulator, which cannot be tapped from a terminal. Nobody holds the
    /// key, so that dependent can never sign in.
    private func registerDemoDependentIfAsked() async {
        guard ProcessInfo.processInfo.arguments.contains("-demoDependent"),
              store.families.isEmpty else { return }
        let dependentKey = LocalWallet.throwawayAddress()
        let dependentAccount = LocalWallet.throwawayAddress()
        let reservoir = LocalWallet.throwawayAddress()
        _ = await store.registerDependent(
            wallet: dependentKey,
            tokenAccount: dependentAccount,
            guardianTokenAccount: reservoir,
            name: "Min Thu"
        )
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
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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
    return OnboardingView()
        .environment(session)
        .environment(Store(session: session))
}
