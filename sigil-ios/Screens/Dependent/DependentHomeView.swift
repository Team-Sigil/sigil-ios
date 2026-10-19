import SwiftUI

struct DependentHomeView: View {
    @Binding var tab: DependentTab
    @State private var asking = false
    @State private var liveRequest: LiveRequest?
    @State private var repeatAsk: ActivityItem?

    /// The signed-in dependent. Only ever their own data (SEC-10).
    private let me = MockData.dependents[0]
    private var budget: Budget { MockData.budget(for: me.id) }
    private var limits: PolicyBody { MockData.policy(for: me.id).body }
    private var guardianName: String { MockData.guardian.shortName }

    var body: some View {
        Screen(spacing: 20) {
            header
            balanceCard
            if liveRequest?.owesReceipt == true {
                owedReceiptCard
            }
            askSection
            policy
            recent
        }
        .sheet(isPresented: $asking) {
            AskSheet(dependent: me) { amount, category, note, emergency in
                startRequest(amount: amount, category: category, note: note, emergency: emergency)
            }
        }
        .onAppear(perform: applyLaunchArguments)
    }

    /// Lets the simulator open the ask sheet, or start an ask of a given size, so
    /// each state can be checked without tapping. Only ever set by a launch argument:
    /// `-openAsk`, or `-askAmount 65 -askCategory clothing`.
    private func applyLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-openAsk") {
            asking = true
        }
        guard let index = arguments.firstIndex(of: "-askAmount"),
              let raw = arguments[safe: index + 1], let whole = Int64(raw) else { return }
        let category = arguments.firstIndex(of: "-askCategory")
            .flatMap { arguments[safe: $0 + 1] }
            .flatMap(Category.init(rawValue:)) ?? .food
        startRequest(amount: Units(whole), category: category,
                     note: "", emergency: arguments.contains("-askEmergency"))
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

    @ViewBuilder private var askSection: some View {
        if let liveRequest {
            LiveRequestCard(request: liveRequest) {
                withAnimation(.snappy) { self.liveRequest = nil }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            VStack(spacing: 12) {
                Button {
                    asking = true
                } label: {
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

                if !repeatable.isEmpty {
                    repeatRow
                }
            }
        }
    }

    /// While a receipt is owed the gateway refuses a new request (409
    /// PROOF_OUTSTANDING), so the app says so plainly instead of letting them ask.
    private var owedReceiptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.orangeOnFill)
                    .frame(width: 44, height: 44)
                    .background(Palette.orange, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send your receipt").font(Typo.body(16, .bold))
                    Text("For the \(liveRequest?.amount.compact ?? "") already sent")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.orangeInk)
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

    /// One tap to repeat something routine, from what was actually sent before.
    private var repeatable: [ActivityItem] {
        MockData.history(for: me.id)
            .filter { $0.outcome == .sentFull && $0.amount > .zero }
            .prefix(3)
            .map { $0 }
    }

    private var repeatRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASK AGAIN")
                .font(Typo.mono(11))
                .tracking(0.9)
                .foregroundStyle(Palette.muted)
            FlowLayout(spacing: 8) {
                ForEach(repeatable) { item in
                    Button {
                        startRequest(amount: item.amount, category: item.category,
                                     note: item.title, emergency: false)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.chevron)
                            Text("\(item.title) \(item.amount.compact)")
                                .font(Typo.body(14, .medium))
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Palette.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The agent run is synchronous and slow, so the card appears straight away in
    /// its waiting state and settles when the answer arrives.
    private func startRequest(amount: Units, category: Category, note: String, emergency: Bool) {
        let request = LiveRequest(amount: amount, category: category, note: note,
                                  emergency: emergency, dependentID: me.id)
        withAnimation(.snappy) { liveRequest = request }

        Task {
            try? await Task.sleep(for: .milliseconds(1_400))
            withAnimation(.snappy) { request.settle() }
        }
    }

    private var policy: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your policy") {
                Text("Set by \(guardianName)").font(Typo.body(13)).foregroundStyle(Palette.muted)
            }
            ListCard {
                InfoRow(title: "Weekly limit", value: limits.weeklyCap.compact)
                InfoRow(title: "Per request, auto-sent", value: "up to \(limits.maxPerRequest.compact)")
                InfoRow(title: "Proof needed over", value: limits.proofThreshold.compact)
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
