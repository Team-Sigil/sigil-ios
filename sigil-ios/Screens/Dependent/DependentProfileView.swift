import SwiftUI

struct DependentProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store

    private var guardianName: String { store.guardianName }
    private var name: String { store.selectedFamily?.dependentName ?? "You" }
    @State private var notifyArrives = true
    @State private var notifyAnswers = true
    @State private var notifyResets = false
    @State private var faceID = true

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
                            Text(store.selectedFamily?.dependentTokenAccount ?? "—")
                                .font(Typo.mono(15, .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack(spacing: 6) {
                                StatusDot(size: 7)
                                Text("Registered by \(guardianName) · devnet")
                            }
                            .font(Typo.body(12))
                            .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                    }
                    Text("This is the only address your allowance can go to. Only \(guardianName) can change it, with their wallet.")
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(2)
                }
                .padding(.vertical, -2)
                .cardStyle(padding: 14)
            }

            LabeledSection(title: "Guardian") {
                Button {} label: {
                    HStack(spacing: 12) {
                        Avatar(initials: "·", background: Palette.ink, foreground: Palette.paper,
                               fontSize: 14, weight: .semibold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guardianName.capitalizedFirstLetter).font(Typo.body(15, .semibold))
                            Text("Funds your allowance · sets your policy")
                                .font(Typo.body(12))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Chevron()
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.vertical, -2)
                    .cardStyle(padding: 14)
                }
                .buttonStyle(.plain)
            }

            LabeledSection(title: "Notify me when") {
                ListCard {
                    ToggleRow(title: "Money arrives", isOn: $notifyArrives)
                    ToggleRow(title: "\(guardianName) answers a request", isOn: $notifyAnswers)
                    ToggleRow(title: "My allowance resets", isOn: $notifyResets)
                }
            }

            LabeledSection(title: "Security & help") {
                ListCard {
                    ToggleRow(title: "Sign in with Face ID", isOn: $faceID)
                    ValueRow(title: "Connected wallet", value: "Devnet", mono: true)
                    ValueRow(title: "Help centre")
                    ValueRow(title: "Terms & privacy")
                }
            }

            SignOutButton { session.signOut() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Avatar(initials: Dependent.initials(of: name), size: 76, fontSize: 24)
            VStack(spacing: 4) {
                Text(name)
                    .font(Typo.display(28))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(session.wallet ?? "")
                    .font(Typo.mono(14, .regular))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button {} label: {
                Text("Edit profile")
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Palette.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

#Preview {
    let session = AppSession()
    return DependentProfileView().environment(session).environment(Store(session: session))
}
