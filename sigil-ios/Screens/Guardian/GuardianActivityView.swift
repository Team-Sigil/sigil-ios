import SwiftUI

struct GuardianActivityView: View {
    private enum Filter: Hashable { case all, sent, needsGuardian, needsProof, stopped }

    @Environment(Store.self) private var store
    @State private var filter: Filter = .all
    @State private var selected: ActivityItem?

    private var groups: [ActivityGroup] {
        store.activityGroups.compactMap { group in
            let items = group.items.filter(matches)
            return items.isEmpty ? nil : ActivityGroup(label: group.label, items: items)
        }
    }

    private func matches(_ item: ActivityItem) -> Bool {
        switch filter {
        case .all: true
        case .sent: item.outcome.isMoneyMoving
        case .needsGuardian: item.outcome.needsGuardian
        case .needsProof: item.outcome == .askedProof
        case .stopped: item.outcome.isStopped
        }
    }

    private var allItems: [ActivityItem] { store.allActivity }

    var body: some View {
        Screen(spacing: 18) {
            PageTitle(title: "Activity", subtitle: "Every decision the agent made, and why.")

            HStack(spacing: 8) {
                statTile(sentLabel, store.sentThisMonth.compact, dark: true)
                statTile("Needs you", "\(allItems.filter { $0.outcome.needsGuardian }.count)")
                statTile("Stopped", "\(allItems.filter(\.outcome.isStopped).count)")
            }

            FilterChips(
                options: [(.all, "All"), (.sent, "Sent"), (.needsGuardian, "Needs you"),
                          (.needsProof, "Needs receipt"), (.stopped, "Declined & blocked")],
                selection: $filter
            )

            if groups.isEmpty {
                Text("Nothing here yet this month.")
                    .font(Typo.body(14))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ForEach(groups) { group in
                    LabeledSection(title: group.label) {
                        ListCard {
                            ForEach(group.items) { item in
                                TappableActivityRow(
                                    item: item,
                                    dependentName: store.name(of: item.dependentID),
                                    showsGuardianSummary: true
                                ) { selected = $0 }
                            }
                        }
                    }
                }
            }
        }
        .refreshable { await store.load() }
        .sheet(item: $selected) { item in
            RequestDetailSheet(item: item, isGuardian: true)
        }
    }

    /// "Sent in Oct" — the month being looked at, not a fixed one.
    private var sentLabel: String {
        "Sent in \(Dates.formatter("MMM").string(from: Date()))"
    }

    private func statTile(_ label: String, _ value: String, dark: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typo.body(12))
                .foregroundStyle(dark ? Palette.mutedOnDark : Palette.muted)
            Text(value)
                .font(Typo.mono(18))
                .foregroundStyle(dark ? Palette.paper : Palette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dark ? Palette.ink : Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if !dark {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1)
            }
        }
    }
}

#Preview {
    let session = AppSession()
    GuardianActivityView()
        .environment(session)
        .environment(Store(session: session))
}
