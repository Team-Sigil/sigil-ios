import SwiftUI

struct GuardianDependentsView: View {
    @Binding var tab: GuardianTab
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store
    @State private var addingDependent = false
    @State private var funding = false

    var body: some View {
        Screen(spacing: 16) {
            HStack(alignment: .top) {
                PageTitle(title: "Dependents", subtitle: subtitle)
                Spacer()
                CircleIconButton(systemImage: "plus", label: "Add dependent", filled: true) {
                    addingDependent = true
                }
            }
            .padding(.bottom, 4)

            ForEach(store.dependents) { dependent in
                DependentCard(
                    onTopUp: { funding = true },
                    dependent: dependent,
                    frozen: session.isFrozen(dependent.familyID),
                    budget: store.budget(for: dependent.familyID),
                    plan: store.planText(for: dependent.familyID),
                    policyVersion: store.policy(for: dependent.familyID)?.version
                ) {
                    session.selectedFamilyID = dependent.familyID
                    tab = .policies
                }
            }

            inviteCard
        }
        .sheet(isPresented: $addingDependent) {
            NavigationStack { OnboardingView() }
        }
        .sheet(isPresented: $funding) { DelegationSheet() }
    }

    private var subtitle: String {
        let count = store.dependents.count
        if count == 0 { return "Nobody yet" }
        return count == 1
            ? "One dependent on your reservoir"
            : "\(count) dependents sharing one reservoir"
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .background(Palette.card, in: Circle())
                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a dependent")
                    .font(Typo.display(18))
                    .accessibilityAddTraits(.isHeader)
                Text("They sign in with their own wallet, then you set their policy. Every dependent you add spends from the same reservoir, so top it up to cover them.")
                    .font(Typo.body(14))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
            }
            Button { addingDependent = true } label: {
                Text("Add them")
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Palette.paper)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Palette.ink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Palette.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }
}

private struct DependentCard: View {
    var onTopUp: () -> Void
    let dependent: Dependent
    let frozen: Bool
    let budget: Budget?
    let plan: String
    let policyVersion: Int?
    var onEditPolicy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Avatar(initials: dependent.initials, size: 52,
                       background: dependent.avatarBackground, foreground: dependent.avatarForeground, fontSize: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dependent.name).font(Typo.display(19)).tracking(-0.2)
                    Text(plan).font(Typo.body(13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if frozen {
                    Text("Frozen")
                        .font(Typo.body(12, .semibold))
                        .foregroundStyle(Palette.orangeInk)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Palette.orangeSoft, in: Capsule())
                } else if let policyVersion {
                    DotBadge(text: "v\(policyVersion)")
                } else {
                    Text("No policy")
                        .font(Typo.body(12, .semibold))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Palette.graySoft, in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week").font(Typo.body(13)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text(budget.map { "\($0.spent.display) of \($0.weeklyCap.compact)" } ?? "—")
                        .font(Typo.mono(13))
                }
                ProgressBar(fraction: budget?.fraction ?? 0)
                Text(budget?.resetText ?? "No budget until a policy is signed")
                    .font(Typo.body(12)).foregroundStyle(Palette.muted)
            }

            HStack(spacing: 8) {
                stat("This month", dependent.sentThisMonth.compact)
                stat("Requests", "\(dependent.requestsThisMonth)")
                stat("Needs you", "\(dependent.awaitingGuardian)", highlighted: dependent.awaitingGuardian > 0)
            }

            HStack(spacing: 10) {
                Button("Top up", action: onTopUp)
                    .buttonStyle(SecondaryButtonStyle())
                Button(policyVersion == nil ? "Set policy" : "Edit policy", action: onEditPolicy)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(2)
        .cardStyle(radius: 24)
    }

    private func stat(_ label: String, _ value: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typo.body(11))
                .foregroundStyle(highlighted ? Palette.orangeInk : Palette.muted)
            Text(value)
                .font(Typo.mono(15))
                .foregroundStyle(highlighted ? Palette.orangeDeep : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Palette.orangeSoft : Palette.paper,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    let session = AppSession()
    GuardianDependentsView(tab: .constant(.dependents))
        .environment(session)
        .environment(Store(session: session))
}
