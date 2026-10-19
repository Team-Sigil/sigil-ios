import SwiftUI

struct DependentProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store

    private var me: Dependent? { store.me }
    private var guardianName: String { store.guardianName }

    var body: some View {
        Screen(spacing: 22) {
            header

            LabeledSection(title: "Money arrives in") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "wallet.pass")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(short(me?.tokenAccount ?? "")).font(Typo.mono(15, .semibold))
                            HStack(spacing: 6) {
                                StatusDot(size: 7)
                                Text("Registered by \(guardianName) · devnet")
                            }
                            .font(Typo.body(12))
                            .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                    }
                    Text("This is the only address your allowance can go to. Only \(guardianName) can change it, with her wallet.")
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(2)
                }
                .padding(.vertical, -2)
                .cardStyle(padding: 14)
            }

            LabeledSection(title: "Guardian") {
                HStack(spacing: 12) {
                    Avatar(initials: "G", background: Palette.ink, foreground: Palette.paper,
                           fontSize: 14, weight: .semibold)
                    VStack(alignment: .leading, spacing: 2) {
                        // The gateway tells a dependent nothing about their guardian
                        // beyond the wallet that funds them, so there is nowhere to go.
                        Text(short(store.guardianWallet)).font(Typo.body(15, .semibold))
                        Text("Funds your allowance · sets your policy")
                            .font(Typo.body(12))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }
                .foregroundStyle(Palette.ink)
                .padding(.vertical, -2)
                .cardStyle(padding: 14)
            }

            LabeledSection(title: "Your wallet") {
                ListCard {
                    ValueRow(title: "Connected wallet", value: short(session.wallet ?? ""), mono: true)
                }
            }

            SignOutButton { session.signOut() }
        }
    }

    /// Addresses are 44 characters; the screens show the ends.
    private func short(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(4))…\(address.suffix(4))"
    }

    private var header: some View {
        VStack(spacing: 10) {
            Avatar(initials: me?.initials ?? "?", size: 76,
                   background: me?.avatarBackground ?? Palette.blueSoft,
                   foreground: me?.avatarForeground ?? Palette.blueInk, fontSize: 24)
            VStack(spacing: 4) {
                Text(me?.name ?? "You")
                    .font(Typo.display(28))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(short(me?.tokenAccount ?? ""))
                    .font(Typo.mono(14, .regular))
                    .foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

#Preview {
    let session = AppSession()
    DependentProfileView()
        .environment(session)
        .environment(Store(session: session))
}
