import SwiftUI

struct GuardianHomeView: View {
    @Binding var tab: GuardianTab
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store
    @State private var confirmingFreeze = false
    @State private var selectedActivity: ActivityItem?

    var body: some View {
        Screen(spacing: 24) {
            header
            agentCard
            dependents
            recentActivity
        }
        .refreshable { await store.load() }
        .sheet(isPresented: $confirmingFreeze) { FreezeSheet() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Dates.today())
                    .font(Typo.mono(12))
                    .tracking(0.7)
                    .foregroundStyle(Palette.muted)
                Text(greeting)
                    .font(Typo.display(28))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button {
                tab = .settings
            } label: {
                Avatar(initials: store.guardian.initials, background: Palette.ink, foreground: Palette.paper, fontSize: 14, weight: .semibold)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
    }

    /// The gateway has no route that sets a display name, so when it doesn't know one the
    /// greeting simply doesn't use a name rather than greeting a wallet address.
    private var greeting: String {
        guard let name = session.displayName, !name.isEmpty else { return "Good evening" }
        return "Good evening, \(name)"
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
                Text(store.sentThisMonth.display)
                    .font(Typo.mono(40))
                    .tracking(-1.2)
                Text(transfersText)
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.mutedOnDark)
            }

            HStack(spacing: 8) {
                darkChip(icon: "drop.fill", text: reservoirText)
                darkChip(icon: "checkmark.shield", text: policiesText)
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
        guard let remaining = store.reservoirRemaining else { return "Reservoir unavailable" }
        return "Shared reservoir \(remaining.compact)"
    }

    private var anyFrozen: Bool { session.frozenCount > 0 }

    private var agentStatusText: String {
        let frozen = session.frozenCount
        guard frozen > 0 else { return "Agent active" }
        return frozen == store.dependents.count
            ? "All frozen"
            : "\(frozen) of \(store.dependents.count) frozen"
    }

    /// Counted from what actually moved this month, not from a fixed figure.
    private var transfersText: String {
        let count = store.transfersThisMonth
        return count == 1 ? "1 request · all within policy"
                          : "\(count) requests · all within policy"
    }

    private var policiesText: String {
        let active = store.dependents.filter { store.policy(for: $0.familyID) != nil }.count
        return active == 1 ? "1 active policy" : "\(active) active policies"
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

    // MARK: Dependents

    private var dependents: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Dependents") {
                LinkButton(title: "Add", systemImage: "plus") { tab = .dependents }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.dependents) { dependent in
                        Button {
                            session.selectedFamilyID = dependent.familyID
                            tab = .dependents
                        } label: {
                            DependentMiniCard(
                                dependent: dependent,
                                budget: store.budget(for: dependent.familyID),
                                plan: store.planText(for: dependent.familyID, short: true)
                            )
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
                ForEach(store.allActivity.prefix(3)) { item in
                    TappableActivityRow(
                        item: item,
                        dependentName: store.name(of: item.dependentID),
                        showsGuardianSummary: true
                    ) { selectedActivity = $0 }
                }
            }
        }
        .sheet(item: $selectedActivity) { item in
            RequestDetailSheet(item: item, isGuardian: true)
        }
    }
}

private struct DependentMiniCard: View {
    let dependent: Dependent
    let budget: Budget?
    let plan: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Avatar(initials: dependent.initials, size: 36,
                       background: dependent.avatarBackground, foreground: dependent.avatarForeground, fontSize: 13)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dependent.name).font(Typo.body(15, .semibold))
                    Text(plan)
                        .font(Typo.body(12)).foregroundStyle(Palette.muted)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ProgressBar(fraction: budget?.fraction ?? 0, height: 6)
                Text(budget.map { "\($0.spent.compact) / \($0.weeklyCap.compact) used" }
                     ?? "No policy yet")
                    .font(Typo.mono(12, .regular))
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(budget?.resetText ?? " ").font(Typo.body(12)).foregroundStyle(Palette.muted)
        }
        .foregroundStyle(Palette.ink)
        .frame(width: 210, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    let session = AppSession()
    GuardianHomeView(tab: .constant(.home))
        .environment(session)
        .environment(Store(session: session))
}
