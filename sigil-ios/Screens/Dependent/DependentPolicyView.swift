import SwiftUI

struct DependentPolicyView: View {
    private let me = MockData.dependents[0]
    private var policy: Policy { MockData.policy(for: me.id) }
    private var limits: Limits { policy.limits }
    private var budget: Budget { MockData.budget(for: me.id) }
    private var guardianName: String { MockData.guardian.shortName }

    var body: some View {
        Screen(spacing: 22) {
            PageTitle(title: "Your policy",
                      subtitle: "Set by \(guardianName) · version \(policy.version) · \(policy.activatedAt)")

            allowanceCard

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "How the agent decides")

                ruleCard(status: .sent, title: "Sent on its own") {
                    Text("Requests up to \(limits.maxPerRequest.compact), as long as you're still inside your weekly \(limits.weeklyCap.compact).")
                }
                ruleCard(status: .needsProof, title: "Needs a receipt") {
                    Text("Anything over \(limits.proofThreshold.compact). Send a photo and the agent carries on.")
                }
                ruleCard(status: .needsGuardian, title: "Goes to \(guardianName) first") {
                    Text("Anything over \(limits.maxPerRequest.compact), or past your weekly limit. She answers with her wallet, so only she can approve it.")
                }
                ruleCard(status: .blocked, title: "Never sent") {
                    FlowLayout(spacing: 6) {
                        ForEach(limits.blockedCategories) { category in
                            Text(category.label)
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
                Button("Ask \(guardianName) to change my policy") {}
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
                    Text("Weekly limit").font(Typo.body(13)).foregroundStyle(Palette.muted)
                    Text(limits.weeklyCap.compact).font(Typo.mono(36)).tracking(-1)
                }
                Spacer()
                Text(budget.resetText).font(Typo.body(13)).foregroundStyle(Palette.textSecondary)
            }
            ProgressBar(fraction: budget.fraction, fill: Palette.accent)
            Text("\(budget.spent.compact) used · \(budget.remaining.compact) left")
                .font(Typo.mono(12, .regular))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(2)
        .cardStyle(radius: 24)
    }

    private func ruleCard<Detail: View>(status: RequestStatus, title: String, @ViewBuilder detail: () -> Detail) -> some View {
        HStack(alignment: .top, spacing: 14) {
            DecisionIcon(status: status)
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
                    Text("Say so, and it goes straight to \(guardianName)").font(Typo.body(13)).foregroundStyle(Palette.orangeInk)
                }
            }
            Text("Tell the agent it's an emergency — medical, safety, getting home. It skips the queue and is checked twice, then \(guardianName) decides. It doesn't lift the limits above, and nothing is sent without her.")
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
    DependentPolicyView()
}
