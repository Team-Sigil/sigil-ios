import SwiftUI

struct ParentActivityView: View {
    private enum Filter: Hashable { case all, sent, held, emergency, declined }

    @State private var filter: Filter = .all

    private var groups: [ActivityGroup] {
        MockData.activity.compactMap { group in
            let items = group.items.filter { item in
                switch filter {
                case .all: true
                case .sent: item.kind == .sent
                case .held: item.kind == .held
                case .emergency: item.kind == .emergency
                case .declined: item.kind == .declined
                }
            }
            return items.isEmpty ? nil : ActivityGroup(label: group.label, items: items)
        }
    }

    var body: some View {
        Screen(spacing: 18) {
            HStack(alignment: .top) {
                PageTitle(title: "Activity", subtitle: "Every decision the agent made, and why.")
                Spacer()
                CircleIconButton(systemImage: "arrow.down.to.line", label: "Export statement")
            }

            HStack(spacing: 8) {
                statTile("Sent in Oct", "$640", dark: true)
                statTile("Held for you", "1")
                statTile("Declined", "1")
            }

            FilterChips(
                options: [(.all, "All"), (.sent, "Sent"), (.held, "Held"), (.emergency, "Emergency"), (.declined, "Declined")],
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
                                ActivityRow(kind: item.kind, title: item.title,
                                            subtitle: "\(item.who) · \(item.reason)",
                                            amount: item.amount, time: item.time)
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
    ParentActivityView()
}
