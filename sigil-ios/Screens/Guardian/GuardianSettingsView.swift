import SwiftUI

struct GuardianSettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store
    @State private var confirmingFreeze = false
    @State private var funding = false

    var body: some View {
        Screen(spacing: 22) {
            PageTitle(title: "Settings")

            HStack(spacing: 14) {
                Avatar(initials: store.guardian.initials, size: 56, background: Palette.ink,
                       foreground: Palette.paper, fontSize: 18, weight: .semibold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.guardian.name).font(Typo.display(19))
                    Text("\(short(store.guardian.wallet)) · Guardian")
                        .font(Typo.mono(13, .regular)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            .foregroundStyle(Palette.ink)
            .cardStyle()

            LabeledSection(title: "Reservoir") {
                ListCard {
                    HStack(spacing: 10) {
                        Text("Wallet").font(Typo.body(15))
                        Spacer()
                        DotBadge(text: "Connected", height: 26)
                    }
                    .frame(minHeight: 52)
                    ValueRow(title: short(store.guardian.wallet), value: "Devnet", mono: true)
                    ValueRow(title: "Token account", value: short(store.guardianTokenAccount), mono: true)
                    ValueRow(title: "Delegated, still unspent",
                             value: store.reservoirRemaining?.compact ?? "Can't read the chain", mono: true)
                    Button { funding = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                            Text("Top up the reservoir").font(Typo.body(15, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text(reservoirNote)
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)
            }

            LabeledSection(title: "Agent") {
                ListCard {
                    Button { confirmingFreeze = true } label: {
                        HStack(spacing: 10) {
                            Text("Freeze transfers").font(Typo.body(15))
                            Spacer()
                            Text(session.frozenCount > 0 ? "\(session.frozenCount) frozen" : "None frozen")
                                .font(Typo.body(14))
                                .foregroundStyle(Palette.textSecondary)
                            Chevron()
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ValueRow(title: "Approving a held request", value: "Wallet signature")
                    ValueRow(title: "Weekly summary", value: "Sundays")
                }
            }

            SignOutButton { session.signOut() }
        }
        .sheet(isPresented: $confirmingFreeze) { FreezeSheet() }
        .sheet(isPresented: $funding) { DelegationSheet() }
    }

    private var reservoirNote: String {
        let count = store.dependents.count
        let who = count == 1 ? "your dependent" : "all \(count) dependents"
        return "One reservoir covers \(who). The money stays in your wallet, and the agent only holds a spending permission you can revoke at any time."
    }

    /// Addresses are 44 characters; rows show the ends, as every other screen does.
    private func short(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(4))…\(address.suffix(4))"
    }
}

struct SignOutButton: View {
    var action: () -> Void

    var body: some View {
        Button("Sign out", action: action)
            .font(Typo.body(15, .semibold))
            .foregroundStyle(Palette.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .buttonStyle(.plain)
    }
}

#Preview {
    let session = AppSession()
    GuardianSettingsView()
        .environment(session)
        .environment(Store(session: session))
}
