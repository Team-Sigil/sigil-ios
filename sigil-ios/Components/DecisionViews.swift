import SwiftUI

/// How one outcome looks. Kept in one place so a new outcome from the gateway only
/// has to be styled once.
private struct OutcomeStyle {
    let icon: String
    let foreground: Color
    let background: Color
    var outlined = false
}

private func style(for outcome: Outcome) -> OutcomeStyle {
    switch outcome {
    case .sentFull:
        OutcomeStyle(icon: "checkmark", foreground: Palette.paper, background: Palette.ink)
    case .sentPartial, .counterOffer:
        OutcomeStyle(icon: "arrow.down.right", foreground: Palette.blueInk, background: Palette.blueSoft)
    case .transferPending:
        OutcomeStyle(icon: "paperplane", foreground: Palette.blueInk, background: Palette.blueSoft)
    case .askedProof:
        OutcomeStyle(icon: "camera", foreground: Palette.orangeInk, background: Palette.orangeSoft)
    case .askedGuardian:
        OutcomeStyle(icon: "clock", foreground: Palette.ink, background: .clear, outlined: true)
    case .auditorFlagged:
        OutcomeStyle(icon: "flag", foreground: Palette.orangeInk, background: Palette.orangeSoft)
    case .askedDependent:
        OutcomeStyle(icon: "questionmark", foreground: Palette.ink, background: .clear, outlined: true)
    case .declined, .outOfScope, .safeFallback, .unknown:
        OutcomeStyle(icon: "xmark", foreground: Palette.segmentOff, background: Palette.graySoft)
    case .blocked:
        OutcomeStyle(icon: "hand.raised", foreground: Palette.danger, background: Palette.dangerSoft)
    }
}

struct DecisionIcon: View {
    let outcome: Outcome

    var body: some View {
        let style = style(for: outcome)
        Image(systemName: style.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(style.foreground)
            .frame(width: 32, height: 32)
            .background(style.background, in: Circle())
            .overlay {
                if style.outlined {
                    Circle().strokeBorder(Palette.borderStrong, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let outcome: Outcome
    var compact = false
    /// Set on dependent-facing screens so "Needs guardian" reads "With Mom".
    var guardianName: String?

    var body: some View {
        let style = style(for: outcome)

        HStack(spacing: 5) {
            Image(systemName: style.icon)
                .font(.system(size: compact ? 9 : 10, weight: .bold))
            Text(guardianName.map(outcome.label(guardianName:)) ?? outcome.label)
                .font(Typo.body(compact ? 11 : 12, .semibold))
        }
        .foregroundStyle(style.foreground)
        .padding(.horizontal, compact ? 8 : 10)
        .frame(height: compact ? 24 : 28)
        .background(style.background, in: Capsule())
        .overlay {
            if style.outlined {
                Capsule().strokeBorder(Palette.borderStrong, lineWidth: 1)
            }
        }
        .accessibilityLabel(outcome.label)
    }
}

/// Small flag chip on a receipt. Only a verified in-app capture reads as reassuring;
/// every other flag is a caution for the person reading it.
struct ProofFlagChip: View {
    let flag: ProofFlag

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: flag.isReassuring ? "checkmark.seal.fill" : "exclamationmark.triangle")
                .font(.system(size: 10, weight: .semibold))
            Text(flag.label)
                .font(Typo.body(12, .medium))
        }
        .foregroundStyle(flag.isReassuring ? Palette.green : Palette.orangeInk)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(flag.isReassuring ? Palette.mint.opacity(0.25) : Palette.orangeSoft, in: Capsule())
    }
}

struct ActivityRow: View {
    let item: ActivityItem
    /// Shown on the guardian's screens, where several dependents are mixed together.
    var showsDependent = true
    /// Guardians read the agent's summary for them; dependents read their own reply.
    var showsGuardianSummary = false
    var guardianName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DecisionIcon(outcome: item.outcome)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Typo.body(14, .semibold))
                    if item.emergencyClaimed {
                        Text("Emergency")
                            .font(Typo.body(10, .bold))
                            .foregroundStyle(Palette.orangeInk)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Palette.orangeSoft, in: Capsule())
                    }
                }
                Text(text)
                    .font(Typo.body(12))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(amountText)
                    .font(Typo.mono(14))
                    .foregroundStyle(item.outcome.isMoneyMoving ? Palette.ink : Palette.muted)
                    .strikethrough(item.outcome.isStopped && item.amount > .zero)
                Text(item.time)
                    .font(Typo.body(11))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        showsDependent ? "\(item.title) · \(MockData.name(of: item.dependentID))" : item.title
    }

    private var text: String {
        showsGuardianSummary ? (item.summaryForGuardian ?? item.reply) : item.reply
    }

    /// `amount_sent` is the source of truth for money, so a part-sent row shows both.
    private var amountText: String {
        if item.outcome == .sentPartial, item.amountSent > .zero {
            return "\(item.amountSent.display) of \(item.amount.compact)"
        }
        return item.amount > .zero ? item.amount.display : "—"
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(Outcome.allCases, id: \.self) { StatusBadge(outcome: $0) }
            }
            ListCard {
                ForEach(MockData.activity[0].items) { ActivityRow(item: $0) }
            }
        }
        .padding()
    }
    .background(Palette.paper)
}
