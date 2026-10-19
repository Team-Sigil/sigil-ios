import SwiftUI

struct GuardianHomeView: View {
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
        .sheet(isPresented: $confirmingFreeze) { FreezeSheet() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("THU 16 OCT")
                    .font(Typo.mono(12))
                    .tracking(0.7)
                    .foregroundStyle(Palette.muted)
                Text("Good evening, \(MockData.guardian.name)")
                    .font(Typo.display(28))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            CircleIconButton(systemImage: "bell", label: "Notifications, 1 new", badge: true)
            Button {
                tab = .settings
            } label: {
                Avatar(initials: MockData.guardian.initials, background: Palette.ink, foreground: Palette.paper, fontSize: 14, weight: .semibold)
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
                        .fill(anyFrozen ? Palette.orange : Palette.mint)
                        .frame(width: 10, height: 10)
                        .background(
                            Circle()
                                .fill((anyFrozen ? Palette.orange : Palette.mint).opacity(0.18))
                                .frame(width: 18, height: 18)
                        )
                    Text(agentStatusText)
                        .font(Typo.body(14, .semibold))
                }
                Spacer()
                Button {
                    confirmingFreeze = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 11, weight: .bold))
                        Text("Freeze")
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
                Text(anyFrozen ? "Sent this month · some frozen" : "Sent this month")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.mutedOnDark)
                Text(MockData.sentThisMonth.display)
                    .font(Typo.mono(40))
                    .tracking(-1.2)
                Text("\(MockData.transfersThisMonth) transfers · all within policy")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.mutedOnDark)
            }

            HStack(spacing: 8) {
                darkChip(icon: "drop.fill", text: reservoirText)
                darkChip(icon: "checkmark.shield", text: "\(MockData.dependents.count) active policies")
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

    /// `delegated_remaining` is null when the crypto layer can't be read, and the
    /// app must say so rather than show a number it made up. The reservoir is one
    /// per guardian, shared by every dependent.
    private var reservoirText: String {
        guard let remaining = MockData.reservoirRemaining else { return "Reservoir unavailable" }
        return "Shared reservoir \(remaining.compact)"
    }

    private var anyFrozen: Bool { session.frozenCount > 0 }

    private var agentStatusText: String {
        let frozen = session.frozenCount
        guard frozen > 0 else { return "Agent active" }
        return frozen == MockData.dependents.count
            ? "All frozen"
            : "\(frozen) of \(MockData.dependents.count) frozen"
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
                    Text("\(MockData.questions.count)")
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
        let question = MockData.questions[0]
        let dependent = MockData.dependent(question.dependentID)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(initials: dependent.initials, background: dependent.avatarBackground,
                       foreground: dependent.avatarForeground, fontSize: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(dependent.name) · \(question.title)").font(Typo.body(15, .semibold))
                    Text("Requested \(question.askedAgo)").font(Typo.body(13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(question.amount.display).font(Typo.mono(20)).tracking(-0.4)
            }

            HStack(alignment: .top, spacing: 10) {
                SigilMark(size: 24)
                Text("\(Text("Agent:").bold().foregroundStyle(Palette.ink)) \(question.agentView)")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let auditorView = question.auditorView {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "flag")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.orangeInk)
                        .padding(.top, 1)
                    Text("\(Text("Auditor:").bold().foregroundStyle(Palette.orangeDeep)) \(auditorView)")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.orangeInk)
                        .lineSpacing(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.orangeSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 10) {
                Button("Decline") { withAnimation(.snappy) { decision = .declined } }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Approve \(question.amount.compact)") { withAnimation(.snappy) { decision = .approved } }
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
                 ? "Approved and signed. \(MockData.questions[0].amount.compact) is on its way to \(MockData.name(of: MockData.questions[0].dependentID))."
                 : "Declined. \(MockData.name(of: MockData.questions[0].dependentID)) has been told why.")
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MockData.dependents) { dependent in
                        Button { tab = .dependents } label: {
                            DependentMiniCard(dependent: dependent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -20)
        }
    }

    // MARK: Activity

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Agent activity") {
                LinkButton(title: "See all") { tab = .activity }
            }
            ListCard {
                ForEach(MockData.activity[0].items.prefix(3)) { item in
                    ActivityRow(item: item, showsGuardianSummary: true)
                }
            }
        }
    }
}

private struct DependentMiniCard: View {
    let dependent: Dependent

    private var budget: Budget { MockData.budget(for: dependent.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Avatar(initials: dependent.initials, size: 36,
                       background: dependent.avatarBackground, foreground: dependent.avatarForeground, fontSize: 13)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dependent.name).font(Typo.body(15, .semibold))
                    Text(MockData.planText(for: dependent.id, short: true))
                        .font(Typo.body(12)).foregroundStyle(Palette.muted)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ProgressBar(fraction: budget.fraction, height: 6)
                Text("\(budget.spent.compact) / \(budget.weeklyCap.compact) used")
                    .font(Typo.mono(12, .regular))
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(budget.resetText).font(Typo.body(12)).foregroundStyle(Palette.muted)
        }
        .foregroundStyle(Palette.ink)
        .frame(width: 210, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    GuardianHomeView(tab: .constant(.home)).environment(AppSession())
}
