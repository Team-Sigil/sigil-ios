import SwiftUI

struct GuardianPoliciesView: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store
    @State private var interviewing = false

    private var dependentID: String { session.selectedFamilyID ?? "" }
    private var policy: Policy? { store.policy(for: dependentID) }

    var body: some View {
        Screen(spacing: 22) {
            PageTitle(title: "Policies", subtitle: "The agent checks every request against these rules.")

            if store.dependents.count > 1 {
                // Every guardian call about one dependent names that family in the
                // X-Family-Id header, so picking one here sets it for everything.
                FilterChips(
                    options: store.dependents.map { ($0.familyID, $0.name) },
                    selection: Binding(
                        get: { dependentID },
                        set: { id in
                            session.selectedFamilyID = id
                            Task { await store.load() }
                        }
                    )
                )
            }

            if let policy {
                content(policy)
            } else {
                noPolicy
            }
        }
        .sheet(isPresented: $interviewing) {
            PolicyInterviewView()
        }
        .task { await store.load() }
    }

    /// Nothing is in force until the guardian has signed one.
    private var noPolicy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No policy yet")
                .font(Typo.display(20))
                .tracking(-0.3)
            Text("Talk to the agent about what this dependent should be able to ask for. You'll see the limits it drafts, and nothing takes effect until you sign them.")
                .font(Typo.body(15))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(3)
            Button("Set the policy") { interviewing = true }
                .buttonStyle(PrimaryButtonStyle(height: 52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: 24)
    }

    @ViewBuilder
    private func content(_ policy: Policy) -> some View {
        let body_ = policy.body

        Group {

            LabeledSection(title: "Allowance") {
                ListCard {
                    if let allowance = body_.allowance {
                        ValueRow(title: "Amount", value: allowance.amount.compact, mono: true)
                        ValueRow(title: "Sent every", value: allowance.weekday.label)
                    } else {
                        ValueRow(title: "Scheduled allowance", value: "None")
                        ValueRow(title: "How money moves", value: "By request")
                    }
                }
            }

            LabeledSection(title: "Outer limits") {
                ListCard {
                    ValueRow(title: "Weekly cap", value: body_.weeklyCap.compact, mono: true)
                    ValueRow(title: "Most per request", value: body_.maxPerRequest.compact, mono: true)
                    ValueRow(title: "Proof needed over", value: body_.proofThreshold.compact, mono: true)
                    ValueRow(title: "Auditor reviews over",
                             value: reviewThresholdText(body_), mono: true)
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
                    ForEach(body_.blockedCategories) { category in
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

            guidanceSection(body_)

            LabeledSection(title: "Paid from (shared)") {
                HStack(spacing: 12) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.paper)
                        .frame(width: 44, height: 30)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shared reservoir").font(Typo.body(15, .semibold))
                        Text(reservoirText)
                            .font(Typo.body(12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    LinkButton(title: "Top up")
                }
                .padding(.vertical, -2)
                .cardStyle(padding: 14)
            }

            versionFooter(policy)

            Button("Change the policy") { interviewing = true }
                .buttonStyle(SecondaryButtonStyle(height: 50))
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
                Text("These are the limits you signed. The agent decides inside them; the engine refuses anything outside.")
                    .font(Typo.body(15))
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Palette.paper)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Guidance is intent, not a rule: the agent reads it, code never enforces it,
    /// and the dependent never sees it. The gateway stores it as one block of text.
    private func guidanceSection(_ body_: PolicyBody) -> some View {
        LabeledSection(title: "What you told the agent") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.chevron)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
                Text(body_.guidance)
                    .font(Typo.body(14))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardStyle(padding: 14)

            Text("Guidance shapes what the agent decides. It is never a limit, and \(store.dependent(familyID: dependentID)?.name ?? "they") can't see it.")
                .font(Typo.body(13))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
                .padding(.horizontal, 4)
        }
    }

    /// The engine falls back to 25% of the weekly cap when the guardian set no
    /// threshold, so the screen says which of the two is in force.
    private func reviewThresholdText(_ body_: PolicyBody) -> String {
        let value = body_.effectiveReviewThreshold.compact
        return body_.usesDefaultReviewThreshold ? "\(value) (default)" : value
    }

    private var reservoirText: String {
        guard let remaining = store.budget?.delegatedRemaining else {
            return "The chain can't be read right now"
        }
        return "\(remaining.compact) left of what you delegated"
    }

    private func versionFooter(_ policy: Policy) -> some View {
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
    let session = AppSession()
    return GuardianPoliciesView().environment(session).environment(Store(session: session))
}
