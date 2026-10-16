import SwiftUI

struct StudentRequestsView: View {
    @Binding var tab: StudentTab

    private enum Filter: Hashable { case all, pending, sent, declined }

    @State private var filter: Filter = .all

    private var history: [StudentRequest] {
        MockData.studentHistory.filter { item in
            switch filter {
            case .all: true
            case .pending: false
            case .sent: item.kind == .sent
            case .declined: item.kind == .declined
            }
        }
    }

    var body: some View {
        Screen(spacing: 18) {
            HStack(alignment: .top) {
                PageTitle(title: "Requests", subtitle: "$120 received this week")
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
                options: [(.all, "All"), (.pending, "Pending"), (.sent, "Sent"), (.declined, "Declined")],
                selection: $filter,
                scrolls: false
            )

            if filter == .all || filter == .pending {
                pendingCard
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

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Textbooks").font(Typo.body(13)).foregroundStyle(Palette.muted)
                    Text("$180.00").font(Typo.mono(30)).tracking(-0.9)
                }
                Spacer()
                StatusBadge(kind: .pending)
            }

            VStack(alignment: .leading, spacing: 0) {
                TimelineStep(state: .done, lineColor: Palette.ink) {
                    Text("You asked \(Text("· 10:02 pm").font(Typo.mono(12, .regular)).foregroundStyle(Palette.muted))")
                        .font(Typo.body(14, .semibold))
                    Text("“Need the two textbooks for Thermodynamics.” Receipt attached.")
                }
                TimelineStep(state: .done, lineColor: Palette.borderStrong) {
                    Text("Agent checked your policy").font(Typo.body(14, .semibold))
                    Text("It’s over your $60 per-request limit, so it went to Mom.")
                }
                TimelineStep(state: .current, lineColor: nil) {
                    Text("Waiting for Mom").font(Typo.body(14, .semibold))
                    Text("You’ll get a notification as soon as she decides.")
                }
            }

            HStack(spacing: 10) {
                Button("Add a note") {}
                    .buttonStyle(SecondaryButtonStyle())
                Button("Cancel request") {}
                    .buttonStyle(SecondaryButtonStyle(foreground: Palette.danger))
            }
        }
        .padding(2)
        .cardStyle(radius: 24)
    }

    private func historyRow(_ item: StudentRequest) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(Typo.body(14, .semibold))
                Text(item.reason).font(Typo.body(12)).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                Text(item.amount)
                    .font(Typo.mono(14))
                    .foregroundStyle(item.kind == .declined ? Palette.muted : Palette.ink)
                    .strikethrough(item.kind == .declined)
                StatusBadge(kind: item.kind, compact: true)
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
    StudentRequestsView(tab: .constant(.requests))
}
