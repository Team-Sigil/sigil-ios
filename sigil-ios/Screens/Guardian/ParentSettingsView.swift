import SwiftUI

struct ParentSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var agentActive = true
    @State private var faceIDApprove = true
    @State private var notifyEvery = false
    @State private var notifyHeld = true
    @State private var faceIDLogin = true

    var body: some View {
        Screen(spacing: 22) {
            PageTitle(title: "Settings")

            Button {} label: {
                HStack(spacing: 14) {
                    Avatar(initials: "HN", size: 56, background: Palette.ink, foreground: Palette.paper,
                           fontSize: 18, weight: .semibold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hnin").font(Typo.display(19))
                        Text("hnin@example.com · Guardian").font(Typo.body(13)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Chevron()
                }
                .foregroundStyle(Palette.ink)
                .cardStyle()
            }
            .buttonStyle(.plain)

            LabeledSection(title: "Payments") {
                ListCard {
                    Button {} label: {
                        HStack(spacing: 10) {
                            Text("Stripe account").font(Typo.body(15))
                            Spacer()
                            DotBadge(text: "Connected", height: 26)
                            Chevron()
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ValueRow(title: "Visa •••• 4242", value: "Default")
                    Button {} label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                            Text("Add a card").font(Typo.body(15, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            LabeledSection(title: "Agent") {
                ListCard {
                    ToggleRow(title: "Agent active", isOn: $agentActive)
                    ToggleRow(title: "Face ID to approve held requests", isOn: $faceIDApprove)
                    ValueRow(title: "Weekly summary", value: "Sundays")
                }
            }

            LabeledSection(title: "Notify me about") {
                ListCard {
                    ToggleRow(title: "Every transfer", isOn: $notifyEvery)
                    ToggleRow(title: "Requests held for me", isOn: $notifyHeld)
                    HStack {
                        Text("Emergency transfers").font(Typo.body(15))
                        Spacer()
                        Text("Always on").font(Typo.body(13)).foregroundStyle(Palette.muted)
                    }
                    .frame(minHeight: 52)
                }
            }

            LabeledSection(title: "Security") {
                ListCard {
                    ToggleRow(title: "Sign in with Face ID", isOn: $faceIDLogin)
                    ValueRow(title: "Change password")
                }
            }

            LabeledSection(title: "Help") {
                ListCard {
                    ValueRow(title: "Help centre")
                    ValueRow(title: "Terms & privacy")
                }
            }

            SignOutButton { session.signOut() }
        }
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
    ParentSettingsView().environment(AppSession())
}
