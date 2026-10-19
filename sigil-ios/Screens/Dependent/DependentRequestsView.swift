import SwiftUI

struct DependentRequestsView: View {
    @Binding var tab: DependentTab

    private enum Filter: Hashable { case all, waiting, sent, stopped }

    @Environment(Store.self) private var store
    @State private var filter: Filter = .all
    @State private var retrying = false
    @State private var retryNote: String?

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
                            historyRow(item)
                        }
                    }
                }
            }
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
                    Text("It needs her wallet signature, so only she can decide it.")
                }
            }

            // The one thing a dependent can genuinely do from here. A request can sit
            // waiting on something that has since changed — the reservoir was empty when
            // it was asked and has since been topped up — and this has the agent look at
            // it again. It cannot move money by itself: whatever the agent decides still
            // goes through the engine, and a transfer that already happened is idempotent.
            Button(retrying ? "Asking the agent…" : "Ask the agent to look again") {
                retry(item)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(retrying)

            if let note = retryNote {
                Text(note)
                    .font(Typo.body(12))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
            }
        }
        .padding(2)
        .cardStyle(radius: 24)
    }

    /// Runs the agent again on a request that is still waiting. The outcome lands in the
    /// store, so the card redraws itself; this only reports when nothing changed.
    private func retry(_ item: ActivityItem) {
        Task {
            retrying = true
            retryNote = nil
            defer { retrying = false }
            guard let decision = await store.retry(requestID: item.id) else {
                retryNote = store.problem ?? "The agent didn't answer. Try again in a moment."
                return
            }
            if decision.outcome.needsGuardian {
                retryNote = "Still with \(guardianName) — only her signature can decide it."
            }
        }
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
        }
        .padding(.vertical, 14)
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
