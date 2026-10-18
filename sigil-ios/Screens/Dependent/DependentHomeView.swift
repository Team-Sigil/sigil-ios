import SwiftUI

struct DependentHomeView: View {
    @Binding var tab: DependentTab
    @State private var draft = ""
    @State private var sent = false
    @FocusState private var draftFocused: Bool

    /// The signed-in dependent. Only ever their own data (SEC-10).
    private let me = MockData.dependents[0]
    private var budget: Budget { MockData.budget(for: me.id) }
    private var limits: PolicyBody { MockData.policy(for: me.id).body }
    private var guardianName: String { MockData.guardian.shortName }

    var body: some View {
        Screen(spacing: 20) {
            header
            balanceCard
            askCard
            policy
            recent
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hi, \(me.name)")
                    .font(Typo.display(28))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text("Funded by \(guardianName) · \(MockData.planText(for: me.id, short: true))")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            CircleIconButton(systemImage: "bell", label: "Notifications")
            Button { tab = .profile } label: {
                Avatar(initials: me.initials, background: me.avatarBackground,
                       foreground: me.avatarForeground, fontSize: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Left this week").font(Typo.body(14, .semibold))
                Spacer()
                Text(budget.resetText)
                    .font(Typo.mono(12, .regular))
                    .foregroundStyle(.white.opacity(0.86))
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(budget.remaining.display)
                    .font(Typo.mono(48))
                    .tracking(-1.9)
                Text("of \(budget.weeklyCap.compact)")
                    .font(Typo.body(14))
                    .foregroundStyle(.white.opacity(0.86))
            }
            VStack(alignment: .leading, spacing: 8) {
                ProgressBar(fraction: 1 - budget.fraction, fill: .white, track: .white.opacity(0.24))
                Text("\(budget.spent.compact) spent this week")
                    .font(Typo.body(12))
                    .foregroundStyle(.white.opacity(0.86))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(alignment: .bottomTrailing) {
            OrbitRings(radii: [44, 80, 116], opacities: [0.22, 0.14, 0.12], color: .white)
                .frame(width: 240, height: 240)
                .offset(x: 80, y: 110)
        }
        .background(Palette.accent)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var askCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SigilMark(size: 24)
                Text("Ask the agent").font(Typo.body(15, .semibold))
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("What do you need, and how much? e.g. $25 for lab supplies",
                          text: $draft, axis: .vertical)
                    .lineLimit(2...5)
                    .font(Typo.body(16))
                    .focused($draftFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 64, alignment: .topLeading)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    .onChange(of: draft) { _, newValue in
                        if !newValue.isEmpty { sent = false }
                    }
                    .accessibilityLabel("Ask the agent")

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Palette.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send request")
            }

            FlowLayout(spacing: 8) {
                ForEach(MockData.requestPresets, id: \.label) { preset in
                    Button {
                        draft = preset.text
                    } label: {
                        Text(preset.label)
                            .font(Typo.body(14, .medium))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(Palette.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if sent {
                HStack(spacing: 10) {
                    Image(systemName: "clock").font(.system(size: 14, weight: .semibold))
                    Text("Checking this against your policy…").font(Typo.body(13, .medium))
                }
                .foregroundStyle(Palette.blueInk)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity)
            } else {
                Text("Requests inside your policy are sent in seconds. Anything else goes to \(guardianName) to approve.")
                    .font(Typo.body(12))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
            }
        }
        .cardStyle(radius: 24)
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.snappy) {
            draft = ""
            sent = true
        }
        draftFocused = false
    }

    private var policy: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your policy") {
                Text("Set by \(guardianName)").font(Typo.body(13)).foregroundStyle(Palette.muted)
            }
            ListCard {
                InfoRow(title: "Weekly limit", value: limits.weeklyCap.compact)
                InfoRow(title: "Per request, auto-sent", value: "up to \(limits.maxPerRequest.compact)")
                InfoRow(title: "Receipt needed over", value: limits.proofThreshold.compact)
                InfoRow(title: "Blocked", value: limits.blockedCategories.map(\.label).joined(separator: " · "), mono: false)
            }
            .onTapGesture { tab = .policy }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent requests") {
                LinkButton(title: "See all") { tab = .requests }
            }
            ListCard {
                ForEach(MockData.history(for: me.id).prefix(3)) { item in
                    requestRow(item)
                }
            }
        }
    }

    private func requestRow(_ item: ActivityItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(Typo.body(14, .semibold))
                Text("\(item.amount.display) · \(item.time)")
                    .font(Typo.mono(13, .regular))
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatusBadge(outcome: item.outcome, guardianName: guardianName)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DependentHomeView(tab: .constant(.home))
}
