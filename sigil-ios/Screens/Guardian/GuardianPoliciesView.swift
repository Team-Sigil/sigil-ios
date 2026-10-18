import SwiftUI

struct GuardianPoliciesView: View {
    @State private var dependentID = MockData.dependents[0].id

    private var policy: Policy { MockData.policy(for: dependentID) }
    private var limits: Limits { policy.limits }

    var body: some View {
        Screen(spacing: 22) {
            PageTitle(title: "Policies", subtitle: "The agent checks every request against these rules.")

            FilterChips(
                options: MockData.dependents.map { ($0.id, $0.name) },
                selection: $dependentID
            )

            summaryCard

            LabeledSection(title: "Allowance") {
                ListCard {
                    ValueRow(title: "Amount", value: policy.allowance.amount.compact, mono: true)
                    ValueRow(title: "Cadence", value: policy.allowance.cadence.label)
                    if policy.allowance.cadence == .weekly {
                        ValueRow(title: "Sent on", value: policy.allowance.weekday.label)
                    }
                }
            }

            LabeledSection(title: "Outer limits") {
                ListCard {
                    ValueRow(title: "Weekly cap", value: limits.weeklyCap.compact, mono: true)
                    ValueRow(title: "Most per request", value: limits.maxPerRequest.compact, mono: true)
                    ValueRow(title: "Requests per day", value: "\(limits.maxRequestsPerDay)", mono: true)
                    ValueRow(title: "Receipt needed over", value: limits.proofThreshold.compact, mono: true)
                    ValueRow(title: "Auditor reviews over", value: limits.auditThreshold.compact, mono: true)
                }
                Text("These are enforced by code. The agent can be talked into anything, but it cannot move past this line.")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)
            }

            LabeledSection(title: "Emergency") {
                ListCard {
                    ValueRow(title: "Emergency requests", value: "Always reviewed")
                    ValueRow(title: "Then", value: "Asked of you")
                }
                Text("An emergency never skips a limit. It always goes to the Auditor first, then to you to approve with your wallet.")
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)
            }

            LabeledSection(title: "Never send for") {
                FlowLayout(spacing: 8) {
                    ForEach(limits.blockedCategories) { category in
                        blockedChip(category.label)
                    }
                    Button {} label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                            Text("Add category").font(Typo.body(14, .semibold))
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .overlay(Capsule().strokeBorder(Palette.dashedChip, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                    }
                    .buttonStyle(.plain)
                }
                .cardStyle(padding: 14)
            }

            guidanceSection

            LabeledSection(title: "Paid from") {
                HStack(spacing: 12) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.paper)
                        .frame(width: 44, height: 30)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your reservoir").font(Typo.body(15, .semibold))
                        Text("\(MockData.reservoirRemaining.compact) left of what you delegated")
                            .font(Typo.body(12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    LinkButton(title: "Top up")
                }
                .padding(.vertical, -2)
                .cardStyle(padding: 14)
            }

            versionFooter
        }
    }

    private var summaryCard: some View {
        HStack(alignment: .top, spacing: 12) {
            SigilMark(size: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text("IN PLAIN WORDS")
                    .font(Typo.mono(11, .regular))
                    .tracking(0.9)
                    .foregroundStyle(Palette.mutedOnDark)
                Text(policy.summary)
                    .font(Typo.body(15))
                    .lineSpacing(3)
                    .contentTransition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Palette.paper)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Guidance is intent, not a rule: the agent reads it, code never enforces it,
    /// and the dependent never sees it (SPEC §7, SEC-10).
    private var guidanceSection: some View {
        LabeledSection(title: "What you told the agent") {
            VStack(spacing: 0) {
                ForEach(Array(policy.guidance.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.chevron)
                            .padding(.top, 3)
                            .accessibilityHidden(true)
                        Text(line)
                            .font(Typo.body(14))
                            .foregroundStyle(Palette.textSecondary)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 12)

                    if index < policy.guidance.count - 1 {
                        Divider().overlay(Palette.divider)
                    }
                }
            }
            .cardStyle(padding: 14)

            Text("Guidance shapes what the agent decides. It is never a limit, and \(MockData.dependent(dependentID).name) can't see it.")
                .font(Typo.body(13))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
                .padding(.horizontal, 4)
        }
    }

    private var versionFooter: some View {
        VStack(spacing: 6) {
            Text("Version \(policy.version) · activated \(policy.activatedAt)")
                .font(Typo.body(13))
                .foregroundStyle(Palette.textSecondary)
            Text(policy.bodyHash)
                .font(Typo.mono(12, .regular))
                .foregroundStyle(Palette.muted)
            Text("Signed by your wallet. The agent cannot change any of this on its own.")
                .font(Typo.body(12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func blockedChip(_ label: String) -> some View {
        HStack(spacing: 2) {
            Text(label).font(Typo.body(14, .medium))
            Button {} label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.segmentOff)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(label)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 44)
        .background(Palette.paper, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
    }
}

#Preview {
    GuardianPoliciesView()
}
