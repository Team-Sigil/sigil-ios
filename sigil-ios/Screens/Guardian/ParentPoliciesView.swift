import SwiftUI

struct ParentPoliciesView: View {
    @State private var dependentID = "mt"
    @State private var askForReceipts = true
    @State private var blocked = MockData.blocked

    private var policy: PolicySummary { MockData.policies[dependentID]! }

    var body: some View {
        Screen(spacing: 22) {
            PageTitle(title: "Policies", subtitle: "The agent checks every request against these rules.")

            SegmentedPill(options: [("mt", "Min Thu"), ("sm", "Su Myat")], selection: $dependentID)

            summaryCard

            LabeledSection(title: "Allowance") {
                ListCard {
                    ValueRow(title: "Amount", value: policy.allowance, mono: true)
                    ValueRow(title: "Frequency", value: policy.frequency)
                    ValueRow(title: "Resets", value: policy.reset)
                }
            }

            LabeledSection(title: "Agent rules") {
                ListCard {
                    ValueRow(title: "Auto-send requests up to", value: policy.autoUpTo, mono: true)
                    ValueRow(title: "Above that", value: "Ask me")
                    ValueRow(title: "Requests per day", value: policy.perDay, mono: true)
                    ToggleRow(title: "Ask for a receipt over $50", isOn: $askForReceipts)
                }
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
                    ForEach(blocked[dependentID] ?? [], id: \.self) { label in
                        blockedChip(label)
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
                        Text("$1,240 left of what you delegated").font(Typo.body(12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    LinkButton(title: "Top up")
                }
                .padding(.vertical, -2)
                .cardStyle(padding: 14)
            }

            Text("Last changed 2 Oct by you")
                .font(Typo.mono(12, .regular))
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
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

    private func blockedChip(_ label: String) -> some View {
        HStack(spacing: 2) {
            Text(label).font(Typo.body(14, .medium))
            Button {
                withAnimation(.snappy) {
                    blocked[dependentID]?.removeAll { $0 == label }
                }
            } label: {
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
    ParentPoliciesView()
}
