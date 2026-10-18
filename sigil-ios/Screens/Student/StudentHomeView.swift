import SwiftUI

struct StudentHomeView: View {
    @Binding var tab: StudentTab
    @State private var draft = ""
    @State private var sent = false
    @FocusState private var draftFocused: Bool

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
                Text("Hi, Min Thu")
                    .font(Typo.display(28))
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Text("Funded by Mom · Weekly plan")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            CircleIconButton(systemImage: "bell", label: "Notifications")
            Button { tab = .profile } label: {
                Avatar(initials: "MT", fontSize: 14)
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
                Text("Resets Mon 20 Oct")
                    .font(Typo.mono(12, .regular))
                    .foregroundStyle(.white.opacity(0.86))
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("$30.00")
                    .font(Typo.mono(48))
                    .tracking(-1.9)
                Text("of $150")
                    .font(Typo.body(14))
                    .foregroundStyle(.white.opacity(0.86))
            }
            VStack(alignment: .leading, spacing: 8) {
                ProgressBar(fraction: 0.2, fill: .white, track: .white.opacity(0.24))
                Text("$120 spent across 5 requests")
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
                Text("Requests inside your policy are sent in seconds. Anything else goes to Mom to approve.")
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
                Text("Set by Mom").font(Typo.body(13)).foregroundStyle(Palette.muted)
            }
            ListCard {
                InfoRow(title: "Weekly limit", value: "$150")
                InfoRow(title: "Per request, auto-sent", value: "up to $60")
                InfoRow(title: "Receipt needed over", value: "$50")
                InfoRow(title: "Blocked", value: "Gambling · Alcohol · Nightlife", mono: false)
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
                requestRow("Lab supplies", "$25.00 · 12 min ago", .sent)
                requestRow("Textbooks", "$180.00 · over $60 limit", .pending)
                requestRow("Concert tickets", "$90.00 · blocked category", .declined)
            }
        }
    }

    private func requestRow(_ title: String, _ detail: String, _ kind: DecisionKind) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.body(14, .semibold))
                Text(detail).font(Typo.mono(13, .regular)).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatusBadge(kind: kind)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    StudentHomeView(tab: .constant(.home))
}
