import SwiftUI

struct GuardianActivityView: View {
    private enum Filter: Hashable { case all, sent, needsGuardian, needsProof, stopped }

    @State private var filter: Filter = .all

    private var groups: [ActivityGroup] {
        MockData.activity.compactMap { group in
            let items = group.items.filter(matches)
            return items.isEmpty ? nil : ActivityGroup(label: group.label, items: items)
        }
    }

    private func matches(_ item: ActivityItem) -> Bool {
        switch filter {
        case .all: true
        case .sent: item.status == .sent || item.status == .partlySent
        case .needsGuardian: item.status == .needsGuardian
        case .needsProof: item.status == .needsProof
        case .stopped: item.status == .declined || item.status == .blocked
        }
    }

    private var allItems: [ActivityItem] { MockData.activity.flatMap(\.items) }

    var body: some View {
        Screen(spacing: 18) {
            HStack(alignment: .top) {
                PageTitle(title: "Activity", subtitle: "Every decision the agent made, and why.")
                Spacer()
                CircleIconButton(systemImage: "arrow.down.to.line", label: "Export statement")
            }

            HStack(spacing: 8) {
                statTile("Sent in Oct", MockData.sentThisMonth.compact, dark: true)
                statTile("Needs you", "\(allItems.filter { $0.status == .needsGuardian }.count)")
                statTile("Stopped", "\(allItems.filter { $0.status == .declined || $0.status == .blocked }.count)")
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
                                ActivityRow(item: item)
                            }
                        }
                    }
                }
            }
        }
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
    GuardianActivityView()
}
