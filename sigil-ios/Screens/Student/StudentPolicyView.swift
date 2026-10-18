import SwiftUI

struct StudentPolicyView: View {
    var body: some View {
        Screen(spacing: 22) {
            PageTitle(title: "Your policy", subtitle: "Set by Mom · last updated 2 Oct")

            allowanceCard

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "How the agent decides")

                ruleCard(kind: .sent, title: "Sent instantly") {
                    Text("Requests up to $60, as long as you’re still inside your weekly $150.")
                }
                ruleCard(kind: .held, title: "Goes to Mom first") {
                    Text("Anything over $60, or past your weekly limit. Add a receipt for anything over $50.")
                }
                ruleCard(kind: .declined, title: "Never sent") {
                    FlowLayout(spacing: 6) {
                        ForEach(["Gambling", "Alcohol", "Nightlife & events"], id: \.self) { label in
                            Text(label)
                                .font(Typo.body(13, .medium))
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(Palette.paper, in: Capsule())
                                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                        }
                    }
                    .padding(.top, 5)
                }
            }

            emergencyCard

            VStack(spacing: 10) {
                Text("Need different limits?")
                    .font(Typo.body(14))
                    .foregroundStyle(Palette.textSecondary)
                Button("Ask Mom to change my policy") {}
                    .buttonStyle(SecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private var allowanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weekly allowance").font(Typo.body(13)).foregroundStyle(Palette.muted)
                    Text("$150").font(Typo.mono(36)).tracking(-1)
                }
                Spacer()
                Text("Resets every Monday").font(Typo.body(13)).foregroundStyle(Palette.textSecondary)
            }
            ProgressBar(fraction: 0.8, fill: Palette.accent)
            Text("$120 used · $30 left")
                .font(Typo.mono(12, .regular))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(2)
        .cardStyle(radius: 24)
    }

    private func ruleCard<Detail: View>(kind: DecisionKind, title: String, @ViewBuilder detail: () -> Detail) -> some View {
        HStack(alignment: .top, spacing: 14) {
            DecisionIcon(kind: kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.body(15, .bold))
                detail()
                    .font(Typo.body(14))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
            }
        }
        .cardStyle()
    }

    private var emergencyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.orangeOnFill)
                    .frame(width: 40, height: 40)
                    .background(Palette.orange, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("If it's an emergency").font(Typo.body(15, .bold))
                    Text("Say so, and it goes straight to Mom").font(Typo.body(13)).foregroundStyle(Palette.orangeInk)
                }
            }
            Text("Tell the agent it's an emergency — medical, safety, getting home. It skips the queue and is checked twice, then Mom decides. It doesn't lift the limits above, and nothing is sent without her.")
                .font(Typo.body(14))
                .foregroundStyle(Palette.orangeInk)
                .lineSpacing(2)
        }
        .foregroundStyle(Palette.orangeDeep)
        .padding(2)
        .cardStyle(radius: 24, fill: Palette.orangeSoft, stroke: Palette.orangeBorder)
    }
}

#Preview {
    StudentPolicyView()
}
