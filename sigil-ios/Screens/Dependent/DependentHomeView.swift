import SwiftUI

struct DependentHomeView: View {
    @Binding var tab: DependentTab
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store

    @State private var asking = false
    @State private var live: LiveRequest?

    private var budget: Budget? { store.budget }
    private var limits: PolicyBody? { store.policy?.body }
    private var guardianName: String { store.guardianName }

    var body: some View {
        Screen(spacing: 20) {
            header
            if let budget {
                balanceCard(budget)
            } else {
                noPolicyCard
            }
            if store.owesReceipt != nil || live?.owesReceipt == true {
                owedReceiptCard
            }
            askSection
            if let limits { policy(limits) }
            recent
        }
        .refreshable { await store.load() }
        .sheet(isPresented: $asking) {
            if let limits, let budget {
                AskSheet(policy: limits, budget: budget, guardianName: guardianName) {
                    amount, category, note, emergency in
                    startRequest(amount: amount, category: category, note: note, emergency: emergency)
                }
            }
        }
        .task { await store.load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hi\(store.selectedFamily?.dependentName.map { ", \($0)" } ?? "")")
                    .font(Typo.display(28))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                if let limits {
                    Text("Weekly cap · \(limits.weeklyCap.compact)")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.muted)
                }
            }
            Spacer()
            CircleIconButton(systemImage: "bell", label: "Notifications",
                             badge: store.notifications.contains { !$0.isRead })
            Button { tab = .profile } label: {
                Avatar(initials: Dependent.initials(of: store.selectedFamily?.dependentName ?? "?"),
                       fontSize: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
    }

    private func balanceCard(_ budget: Budget) -> some View {
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

    /// Nothing can be asked for until the guardian has signed a policy.
    private var noPolicyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing set up yet")
                .font(Typo.body(16, .bold))
            Text("\(guardianName.capitalizedFirstLetter) hasn't signed a policy for you yet. Once they do, you'll see what you can ask for here.")
                .font(Typo.body(14))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 24)
    }

    @ViewBuilder private var askSection: some View {
        if let live {
            LiveRequestCard(request: live, guardianName: guardianName) {
                withAnimation(.snappy) { self.live = nil }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else if limits != nil {
            VStack(spacing: 12) {
                Button { asking = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                        Text("Ask for money").font(Typo.body(17, .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.owesReceipt != nil)
                .opacity(store.owesReceipt != nil ? 0.4 : 1)

                if let problem = store.problem {
                    Text(problem)
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// While a receipt is owed the gateway refuses a new request with
    /// `409 PROOF_OUTSTANDING`, so the app says so plainly instead of letting them ask.
    private var owedReceiptCard: some View {
        let amount = store.owesReceipt.map { Units(raw: $0.amount) } ?? live?.amount

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.orangeOnFill)
                    .frame(width: 44, height: 44)
                    .background(Palette.orange, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send your receipt").font(Typo.body(16, .bold))
                    if let amount {
                        Text("For the \(amount.compact) already sent")
                            .font(Typo.body(13))
                            .foregroundStyle(Palette.orangeInk)
                    }
                }
            }
            Text("You can't ask for money again until the receipt has been checked and accepted.")
                .font(Typo.body(13))
                .foregroundStyle(Palette.orangeInk)
                .lineSpacing(2)
        }
        .foregroundStyle(Palette.orangeDeep)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(fill: Palette.orangeSoft, stroke: Palette.orangeBorder)
    }

    private func policy(_ limits: PolicyBody) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your policy") {
                Text("Set by \(guardianName)").font(Typo.body(13)).foregroundStyle(Palette.muted)
            }
            ListCard {
                InfoRow(title: "Weekly limit", value: limits.weeklyCap.compact)
                InfoRow(title: "Per request, auto-sent", value: "up to \(limits.maxPerRequest.compact)")
                InfoRow(title: "Proof needed over", value: limits.proofThreshold.compact)
                if !limits.blockedCategories.isEmpty {
                    InfoRow(
                        title: "Blocked",
                        value: limits.blockedCategories.map(\.label).joined(separator: " · "),
                        mono: false
                    )
                }
            }
            .onTapGesture { tab = .policy }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent requests") {
                LinkButton(title: "See all") { tab = .requests }
            }
            if store.requests.isEmpty {
                Text("Nothing yet. What you ask for will show up here.")
                    .font(Typo.body(14))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                ListCard {
                    ForEach(store.requests.prefix(3)) { item in
                        requestRow(item)
                    }
                }
            }
        }
    }

    private func requestRow(_ item: ActivityItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(Typo.body(14, .semibold)).lineLimit(1)
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

    /// The agent decides, and it can take a minute, so the card appears straight away in
    /// its waiting state and settles on whatever comes back.
    private func startRequest(amount: Units, category: Category, note: String, emergency: Bool) {
        let request = LiveRequest(
            amount: amount, category: category, note: note, emergency: emergency,
            proofThreshold: limits?.proofThreshold ?? .zero
        )
        withAnimation(.snappy) { live = request }

        Task {
            let decision = await store.ask(
                amount: amount, category: category, purpose: note, emergency: emergency
            )
            withAnimation(.snappy) {
                if let decision {
                    request.settle(with: decision)
                } else {
                    live = nil
                }
            }
        }
    }
}

extension String {
    var capitalizedFirstLetter: String {
        isEmpty ? self : prefix(1).uppercased() + dropFirst()
    }
}
