import SwiftUI

struct DependentRequestsView: View {
    @Binding var tab: DependentTab

    private enum Filter: Hashable { case all, waiting, sent, stopped }

    @Environment(Store.self) private var store
    @State private var filter: Filter = .all
    @State private var selected: ActivityItem?

    private var me: Dependent? { store.me }
    private var guardianName: String { store.guardianName }
    private var budget: Budget? { me.flatMap { store.budget(for: $0.familyID) } }

    private var pending: ActivityItem? {
        store.history(forFamily: me?.familyID).first { $0.outcome.needsGuardian }
    }

    private var history: [ActivityItem] {
        store.history(forFamily: me?.familyID).filter { item in
            switch filter {
            case .all: true
            case .waiting: item.outcome.needsGuardian || item.outcome == .askedProof
                || item.outcome == .awaitingDecision
            case .sent: item.outcome.isMoneyMoving
            case .stopped: item.outcome.isStopped
            }
        }
    }

    var body: some View {
        Screen(spacing: 18) {
            HStack(alignment: .top) {
                PageTitle(title: "Requests",
                          subtitle: "\((budget?.spent ?? .zero).compact) received this week")
                Spacer()
                Button { tab = .home } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        Text("New").font(Typo.body(14, .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            FilterChips(
                options: [(.all, "All"), (.waiting, "Waiting"), (.sent, "Sent"), (.stopped, "Stopped")],
                selection: $filter
            )

            if let pending, filter == .all || filter == .waiting {
                pendingCard(pending)
                    .task(id: pending.id) { await store.loadThread(pending.id) }
            }

            if !history.isEmpty {
                LabeledSection(title: "This week") {
                    ListCard {
                        ForEach(history) { item in
                            Button { selected = item } label: {
                                historyRow(item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows the details")
                        }
                    }
                }
            } else if pending == nil {
                Text(filter == .all ? "No requests yet. Tap New to ask for money." : "Nothing here.")
                    .font(Typo.body(14))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }
        }
        .refreshable { await store.load() }
        .sheet(item: $selected) { item in
            RequestDetailSheet(item: item, isGuardian: false) { tab = .home }
        }
    }

    private func pendingCard(_ item: ActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(Typo.body(13)).foregroundStyle(Palette.muted)
                    Text(item.amount.display).font(Typo.mono(30)).tracking(-0.9)
                }
                Spacer()
                StatusBadge(outcome: item.outcome, guardianName: guardianName)
            }
            .contentShape(Rectangle())
            .onTapGesture { selected = item }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((store.threads[item.id] ?? []).enumerated()), id: \.element.id) { index, entry in
                    TimelineStep(state: .done,
                                 lineColor: index == 0 ? Palette.ink : Palette.borderStrong) {
                        Text("\(entry.role == .dependent ? "You" : "Agent") \(Text("· \(entry.at)").font(Typo.mono(12, .regular)).foregroundStyle(Palette.muted))")
                            .font(Typo.body(14, .semibold))
                        Text(entry.text)
                    }
                }
                TimelineStep(state: .current, lineColor: nil) {
                    Text("Waiting for \(guardianName)").font(Typo.body(14, .semibold))
                    Text("It needs their wallet signature, so only they can decide it.")
                }
            }

            // Deliberately nothing that runs the agent again: every run on a request that
            // is waiting for the guardian files another question for them to answer.
            Text("Nothing to do but wait. You'll see the answer here as soon as they sign.")
                .font(Typo.body(12))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)

            LinkButton(title: "See full details") { selected = item }
        }
        .padding(2)
        .cardStyle(radius: 24)
    }

    private func historyRow(_ item: ActivityItem) -> some View {
        let stopped = item.outcome.isStopped

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(Typo.body(14, .semibold))
                Text(item.reply).font(Typo.body(12)).foregroundStyle(Palette.muted).lineSpacing(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                Text(item.outcome.isMoneyMoving && item.amountSent > .zero
                     ? item.amountSent.display : item.amount.display)
                    .font(Typo.mono(14))
                    .foregroundStyle(stopped ? Palette.muted : Palette.ink)
                    .strikethrough(stopped)
                StatusBadge(outcome: item.outcome, compact: true, guardianName: guardianName)
            }
            Chevron()
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineStep<Content: View>: View {
    enum Marker { case done, current }

    let state: Marker
    let lineColor: Color?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                marker
                if let lineColor {
                    Rectangle().fill(lineColor).frame(width: 2).frame(minHeight: 14)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .font(Typo.body(13))
            .foregroundStyle(Palette.ink)
            .lineSpacing(2)
            .padding(.bottom, lineColor == nil ? 0 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var marker: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Palette.paper)
                .frame(width: 20, height: 20)
                .background(Palette.ink, in: Circle())
        case .current:
            Circle()
                .fill(Palette.accent)
                .frame(width: 8, height: 8)
                .frame(width: 20, height: 20)
                .background(Color.white, in: Circle())
                .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 2))
        }
    }
}

#Preview {
    let session = AppSession()
    DependentRequestsView(tab: .constant(.requests))
        .environment(session)
        .environment(Store(session: session))
}
