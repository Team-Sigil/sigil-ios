import SwiftUI

struct DecisionIcon: View {
    let status: RequestStatus

    var body: some View {
        switch status {
        case .sent:
            symbol("checkmark", weight: .bold)
                .foregroundStyle(Palette.paper)
                .background(Palette.ink, in: Circle())
        case .partlySent:
            symbol("arrow.down.right", weight: .bold)
                .foregroundStyle(Palette.blueInk)
                .background(Palette.blueSoft, in: Circle())
        case .needsProof:
            symbol("camera", weight: .semibold)
                .foregroundStyle(Palette.orangeInk)
                .background(Palette.orangeSoft, in: Circle())
        case .needsGuardian:
            symbol("clock", weight: .semibold)
                .foregroundStyle(Palette.ink)
                .background(Circle().strokeBorder(Palette.borderStrong, lineWidth: 1))
        case .declined:
            symbol("xmark", weight: .bold)
                .foregroundStyle(Palette.segmentOff)
                .background(Palette.graySoft, in: Circle())
        case .blocked:
            symbol("hand.raised", weight: .semibold)
                .foregroundStyle(Palette.danger)
                .background(Palette.dangerSoft, in: Circle())
        }
    }

    private func symbol(_ name: String, weight: Font.Weight) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: weight))
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let status: RequestStatus
    var compact = false
    /// Set on dependent-facing screens so "Needs guardian" reads "With Mom".
    var guardianName: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: compact ? 9 : 10, weight: .bold))
            Text(guardianName.map(label(guardianName:)) ?? status.label)
                .font(Typo.body(compact ? 11 : 12, .semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, compact ? 8 : 10)
        .frame(height: compact ? 24 : 28)
        .background(background, in: Capsule())
        .overlay {
            if status == .needsGuardian {
                Capsule().strokeBorder(Palette.borderStrong, lineWidth: 1)
            }
        }
        .accessibilityLabel(status.label)
    }

    private func label(guardianName: String) -> String {
        status.label(guardianName: guardianName)
    }

    private var icon: String {
        switch status {
        case .sent: "checkmark"
        case .partlySent: "arrow.down.right"
        case .needsProof: "camera"
        case .needsGuardian: "clock"
        case .declined: "xmark"
        case .blocked: "hand.raised"
        }
    }

    private var foreground: Color {
        switch status {
        case .sent: Palette.paper
        case .partlySent: Palette.blueInk
        case .needsProof: Palette.orangeInk
        case .needsGuardian: Palette.ink
        case .declined: Palette.segmentOff
        case .blocked: Palette.danger
        }
    }

    private var background: Color {
        switch status {
        case .sent: Palette.ink
        case .partlySent: Palette.blueSoft
        case .needsProof: Palette.orangeSoft
        case .needsGuardian: .clear
        case .declined: Palette.graySoft
        case .blocked: Palette.dangerSoft
        }
    }
}

struct ActivityRow: View {
    let item: ActivityItem
    /// Shown on the guardian's screens, where several dependents are mixed together.
    var showsDependent = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DecisionIcon(status: item.status)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typo.body(14, .semibold))
                Text(item.note)
                    .font(Typo.body(12))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(1)
                if let verdict = item.verdict, verdict.verdict == .flag {
                    Text(verdict.reason)
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.orangeInk)
                        .lineSpacing(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(amountText)
                    .font(Typo.mono(14))
                    .foregroundStyle(isSpent ? Palette.ink : Palette.muted)
                    .strikethrough(item.status == .blocked || item.status == .declined)
                Text(item.time)
                    .font(Typo.body(11))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        showsDependent ? "\(item.title) · \(MockData.name(of: item.dependentID))" : item.title
    }

    private var amountText: String {
        guard let sent = item.sentAmount else { return item.amount.display }
        return "\(sent.display) of \(item.amount.compact)"
    }

    private var isSpent: Bool {
        item.status == .sent || item.status == .partlySent
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach([RequestStatus.sent, .partlySent, .needsProof], id: \.self) { StatusBadge(status: $0) }
            }
            HStack(spacing: 8) {
                ForEach([RequestStatus.needsGuardian, .declined, .blocked], id: \.self) { StatusBadge(status: $0) }
            }
            ListCard {
                ForEach(MockData.activity[0].items) { ActivityRow(item: $0) }
            }
        }
        .padding()
    }
    .background(Palette.paper)
}
