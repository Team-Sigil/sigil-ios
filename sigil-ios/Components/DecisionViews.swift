import SwiftUI

/// Round icon showing how the agent handled a request.
struct DecisionIcon: View {
    let kind: DecisionKind
    var size: CGFloat = 40

    var body: some View {
        Group {
            switch kind {
            case .sent:
                symbol("checkmark", weight: .bold)
                    .foregroundStyle(Palette.blueInk)
                    .background(Palette.blueSoft, in: Circle())
            case .held, .pending:
                symbol("clock", weight: .semibold)
                    .foregroundStyle(Palette.ink)
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
            case .emergency:
                symbol("exclamationmark.triangle", weight: .semibold)
                    .foregroundStyle(Palette.orangeInk)
                    .background(Palette.orangeSoft, in: Circle())
            case .declined:
                symbol("xmark", weight: .bold)
                    .foregroundStyle(Palette.segmentOff)
                    .background(Palette.graySoft, in: Circle())
            }
        }
        .accessibilityHidden(true)
    }

    private func symbol(_ name: String, weight: Font.Weight) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.4, weight: weight))
            .frame(width: size, height: size)
    }
}

/// Small status pill: Sent / With Mom / Declined.
struct StatusBadge: View {
    let kind: DecisionKind
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            Image(systemName: icon)
                .font(.system(size: compact ? 9 : 10, weight: .heavy))
            Text(label)
                .font(Typo.body(compact ? 11 : 12, .semibold))
        }
        .padding(.horizontal, compact ? 8 : 10)
        .frame(height: compact ? 24 : 28)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .overlay {
            if kind == .pending || kind == .held {
                Capsule().strokeBorder(Palette.ink, lineWidth: 1)
            }
        }
    }

    private var label: String {
        switch kind {
        case .sent: "Sent"
        case .held, .pending: "With Mom"
        case .emergency: "Emergency"
        case .declined: "Declined"
        }
    }

    private var icon: String {
        switch kind {
        case .sent: "checkmark"
        case .held, .pending: "clock"
        case .emergency: "exclamationmark.triangle"
        case .declined: "xmark"
        }
    }

    private var foreground: Color {
        switch kind {
        case .sent: Palette.paper
        case .held, .pending: Palette.ink
        case .emergency: Palette.orangeInk
        case .declined: Palette.segmentOff
        }
    }

    private var background: Color {
        switch kind {
        case .sent: Palette.ink
        case .held, .pending: .clear
        case .emergency: Palette.orangeSoft
        case .declined: Palette.graySoft
        }
    }
}

/// Activity row used on the guardian home and activity screens.
struct ActivityRow: View {
    let kind: DecisionKind
    let title: String
    let subtitle: String
    let amount: String
    var time: String?

    var body: some View {
        HStack(spacing: 12) {
            DecisionIcon(kind: kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.body(14, .semibold))
                Text(subtitle)
                    .font(Typo.body(12))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(amount)
                    .font(Typo.mono(14))
                    .foregroundStyle(kind == .declined ? Palette.muted : Palette.ink)
                    .strikethrough(kind == .declined)
                if let time {
                    Text(time)
                        .font(Typo.mono(11, .regular))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
