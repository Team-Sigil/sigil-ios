import SwiftUI

struct ParentHomeView: View {
    @Binding var tab: GuardianTab
    @Environment(AppSession.self) private var session
    @State private var decision: Decision?
    @State private var confirmingFreeze = false

    private enum Decision { case approved, declined }

    var body: some View {
        Screen(spacing: 24) {
            header
            agentCard
            approvals
            dependents
            recentActivity
        }
        .sheet(isPresented: $confirmingFreeze) { freezeSheet }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("THU 16 OCT")
                    .font(Typo.mono(12))
                    .tracking(0.7)
                    .foregroundStyle(Palette.muted)
                Text("Good evening, Hnin")
                    .font(Typo.display(28))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            CircleIconButton(systemImage: "bell", label: "Notifications, 1 new", badge: true)
            Button {
                tab = .settings
            } label: {
                Avatar(initials: "HN", background: Palette.ink, foreground: Palette.paper, fontSize: 14, weight: .semibold)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
    }

    // MARK: Agent status

    private var agentCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 10) {
                    Circle()
                        .fill(session.frozen ? Palette.orange : Palette.mint)
                        .frame(width: 10, height: 10)
                        .background(
                            Circle()
                                .fill((session.frozen ? Palette.orange : Palette.mint).opacity(0.18))
                                .frame(width: 18, height: 18)
                        )
                    Text(session.frozen ? "Frozen" : "Agent active")
                        .font(Typo.body(14, .semibold))
                }
                Spacer()
                Button {
                    confirmingFreeze = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: session.frozen ? "play.fill" : "snowflake")
                            .font(.system(size: 11, weight: .bold))
                        Text(session.frozen ? "Unfreeze" : "Freeze")
                            .font(Typo.body(13, .semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .overlay(Capsule().strokeBorder(Palette.paper.opacity(0.28), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(session.frozen ? "Frozen · sent this month" : "Sent this month")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.mutedOnDark)
                Text("$640.00")
                    .font(Typo.mono(40))
                    .tracking(-1.2)
                Text("14 transfers · all within policy")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.mutedOnDark)
            }

            HStack(spacing: 8) {
                darkChip(icon: "drop.fill", text: "Reservoir $1,240 left")
                darkChip(icon: "checkmark.shield", text: "2 active policies")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Palette.paper)
        .background(alignment: .topTrailing) {
            ZStack {
                OrbitRings(radii: [40, 72, 104], opacities: [0.16, 0.10, 0.08])
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 8, height: 8)
                    .offset(x: 48 - 110, y: 146 - 110)
            }
            .frame(width: 220, height: 220)
            .offset(x: 70, y: -60)
        }
        .background(Palette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func darkChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium))
            Text(text).font(Typo.body(12, .medium))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Palette.paper.opacity(0.10), in: Capsule())
    }

    // MARK: Approvals

    private var approvals: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Needs your approval")
                    .font(Typo.display(19))
                    .tracking(-0.2)
                    .accessibilityAddTraits(.isHeader)
                if decision == nil {
                    Text("1")
                        .font(Typo.mono(12, .semibold))
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Palette.orange, in: Capsule())
                }
            }

            if let decision {
                resolvedBanner(decision)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                pendingCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(initials: "MT", fontSize: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Min Thu · Textbooks").font(Typo.body(15, .semibold))
                    Text("Requested 8 min ago").font(Typo.body(13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text("$180.00").font(Typo.mono(20)).tracking(-0.4)
            }

            HStack(alignment: .top, spacing: 10) {
                SigilMark(size: 24)
                Text("\(Text("Agent:").bold().foregroundStyle(Palette.ink)) Above Min Thu’s $60 per-request limit, so I held it for you. A receipt from the campus bookstore is attached.")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button("Decline") { withAnimation(.snappy) { decision = .declined } }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Approve $180") { withAnimation(.snappy) { decision = .approved } }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .cardStyle()
    }

    private func resolvedBanner(_ decision: Decision) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.paper)
                .frame(width: 36, height: 36)
                .background(Palette.ink, in: Circle())
            Text(decision == .approved
                 ? "Approved and signed. $180 is on its way to Min Thu."
                 : "Declined. Min Thu has been told why.")
                .font(Typo.body(14))
                .frame(maxWidth: .infinity, alignment: .leading)
            LinkButton(title: "Undo") { withAnimation(.snappy) { self.decision = nil } }
        }
        .padding(.vertical, -2)
        .cardStyle(padding: 14)
    }

    // MARK: Dependents

    private var dependents: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Dependents") {
                LinkButton(title: "Add", systemImage: "plus") { tab = .dependents }
            }
            HStack(spacing: 12) {
                ForEach(MockData.dependents) { dependent in
                    Button { tab = .dependents } label: {
                        DependentMiniCard(dependent: dependent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Activity

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Agent activity") {
                LinkButton(title: "See all") { tab = .activity }
            }
            ListCard {
                ActivityRow(kind: .sent, title: "Lab supplies → Min Thu",
                            subtitle: "Auto-sent · within per-request limit · 12 min", amount: "$25.00")
                ActivityRow(kind: .emergency, title: "Clinic visit · Su Myat",
                            subtitle: "Emergency category · Auditor reviewed · you approved · Yesterday", amount: "$85.00")
                ActivityRow(kind: .declined, title: "Concert tickets · Min Thu",
                            subtitle: "Declined · Nightlife & events is blocked · Tue", amount: "$90.00")
            }
        }
    }
}

private struct DependentMiniCard: View {
    let dependent: Dependent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Avatar(initials: dependent.initials, size: 36,
                       background: dependent.avatarBackground, foreground: dependent.avatarForeground, fontSize: 13)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dependent.name).font(Typo.body(15, .semibold))
                    Text(dependent.shortPlan).font(Typo.body(12)).foregroundStyle(Palette.muted)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ProgressBar(fraction: dependent.fraction, height: 6)
                Text(dependent.shortUsedText)
                    .font(Typo.mono(12, .regular))
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(dependent.resetText).font(Typo.body(12)).foregroundStyle(Palette.muted)
        }
        .foregroundStyle(Palette.ink)
        .cardStyle()
    }
}

// MARK: Freeze

private extension ParentHomeView {
    var freezeSheet: some View {
        SignatureSheet(
            title: session.frozen ? "Lift the freeze" : "Freeze all transfers",
            summary: session.frozen
                ? "The agent can start sending again, inside the limits you signed."
                : "Nothing moves until you unfreeze, whatever the agent or the dependents ask for.",
            message: [
                "FinGuard:freeze",
                "family:\(MockData.familyID)",
                "frozen:\(session.frozen ? "false" : "true")",
                "nonce:\(MockData.nonce)",
            ],
            confirmTitle: session.frozen ? "Sign and unfreeze" : "Sign and freeze"
        ) {
            withAnimation(.snappy) { session.frozen.toggle() }
        }
    }
}

#Preview {
    ParentHomeView(tab: .constant(.home)).environment(AppSession())
}
