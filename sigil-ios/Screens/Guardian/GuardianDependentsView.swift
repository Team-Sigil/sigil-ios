import SwiftUI

struct GuardianDependentsView: View {
    @Binding var tab: GuardianTab
    @Environment(AppSession.self) private var session

    var body: some View {
        Screen(spacing: 16) {
            HStack(alignment: .top) {
                PageTitle(title: "Dependents",
                          subtitle: "\(MockData.dependents.count) dependents sharing one reservoir")
                Spacer()
                CircleIconButton(systemImage: "plus", label: "Add dependent", filled: true)
            }
            .padding(.bottom, 4)

            ForEach(MockData.dependents) { dependent in
                DependentCard(dependent: dependent, frozen: session.isFrozen(dependent.familyID)) {
                    session.selectedFamilyID = dependent.familyID
                    tab = .policies
                }
            }

            inviteCard
        }
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
            Button {} label: {
                Text("Send invite link")
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
    let dependent: Dependent
    let frozen: Bool
    var onEditPolicy: () -> Void

    private var budget: Budget { MockData.budget(for: dependent.id) }
    private var policy: Policy { MockData.policy(for: dependent.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Avatar(initials: dependent.initials, size: 52,
                       background: dependent.avatarBackground, foreground: dependent.avatarForeground, fontSize: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dependent.name).font(Typo.display(19)).tracking(-0.2)
                    Text(MockData.planText(for: dependent.id)).font(Typo.body(13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if frozen {
                    Text("Frozen")
                        .font(Typo.body(12, .semibold))
                        .foregroundStyle(Palette.orangeInk)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Palette.orangeSoft, in: Capsule())
                } else {
                    DotBadge(text: "v\(policy.version)")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This week").font(Typo.body(13)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("\(budget.spent.display) of \(budget.weeklyCap.compact)").font(Typo.mono(13))
                }
                ProgressBar(fraction: budget.fraction)
                Text(budget.resetText).font(Typo.body(12)).foregroundStyle(Palette.muted)
            }

            HStack(spacing: 8) {
                stat("This month", dependent.sentThisMonth.compact)
                stat("Requests", "\(dependent.requestsThisMonth)")
                stat("Needs you", "\(dependent.awaitingGuardian)", highlighted: dependent.awaitingGuardian > 0)
            }

            HStack(spacing: 10) {
                Button("Top up") {}
                    .buttonStyle(SecondaryButtonStyle())
                Button("Edit policy", action: onEditPolicy)
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
    GuardianDependentsView(tab: .constant(.dependents)).environment(AppSession())
}
