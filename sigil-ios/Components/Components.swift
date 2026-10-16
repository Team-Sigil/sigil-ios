import SwiftUI

// MARK: - Containers

/// Scrollable paper-coloured page used by every tab.
struct Screen<Content: View>: View {
    var spacing: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.paper.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
    }
}

extension View {
    /// White card with hairline border.
    func cardStyle(radius: CGFloat = 20, padding: CGFloat = 16, fill: Color = Palette.card, stroke: Color = Palette.border) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }
}

/// White card whose children are separated by hairline dividers.
struct ListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    subview
                    if subview.id != subviews.last?.id {
                        Rectangle().fill(Palette.divider).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }
}

/// Mono uppercase label above a grouped section.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Typo.mono(11))
            .tracking(0.9)
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Labelled group: section label above content.
struct LabeledSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            content
        }
    }
}

/// Section heading with optional trailing action (e.g. "See all").
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(Typo.display(19))
                .tracking(-0.2)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Large page title with optional subtitle.
struct PageTitle: View {
    let title: String
    var subtitle: String?
    var size: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typo.display(size))
                .tracking(-0.8)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Typo.body(14))
                    .foregroundStyle(Palette.muted)
            }
        }
    }
}

// MARK: - Rows

/// Tappable settings row: title, optional value, chevron.
struct ValueRow: View {
    let title: String
    var value: String?
    var mono = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(Typo.body(15))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(mono ? Typo.mono(14, .regular) : Typo.body(14))
                        .foregroundStyle(Palette.textSecondary)
                }
                Chevron()
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Row with a trailing switch.
struct ToggleRow<Leading: View>: View {
    let title: String
    @Binding var isOn: Bool
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 10) {
            leading
            Toggle(title, isOn: $isOn)
                .font(Typo.body(15))
                .tint(Palette.accent)
        }
        .frame(minHeight: 52)
    }
}

extension ToggleRow where Leading == EmptyView {
    init(title: String, isOn: Binding<Bool>) {
        self.init(title: title, isOn: isOn) { EmptyView() }
    }
}

/// Non-interactive row with trailing text.
struct InfoRow: View {
    let title: String
    let value: String
    var mono = true
    var titleColor: Color = Palette.textSecondary
    var titleSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Typo.body(titleSize))
                .foregroundStyle(titleColor)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? Typo.mono(14) : Typo.body(13, .medium))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 48)
    }
}

struct Chevron: View {
    var color: Color = Palette.chevron

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

// MARK: - Small pieces

struct Avatar: View {
    let initials: String
    var size: CGFloat = 44
    var background: Color = Palette.blueSoft
    var foreground: Color = Palette.blueInk
    var fontSize: CGFloat?
    var weight: Font.Weight = .bold

    var body: some View {
        Text(initials)
            .font(Typo.body(fontSize ?? size * 0.33, weight))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: Circle())
    }
}

struct ProgressBar: View {
    let fraction: Double
    var height: CGFloat = 8
    var fill: Color = Palette.ink
    var track: Color = Palette.track

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

struct StatusDot: View {
    var color: Color = Palette.green
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// Small pill with a green dot, e.g. "Agent on", "Connected".
struct DotBadge: View {
    let text: String
    var dot: Color = Palette.green
    var height: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(color: dot, size: 7)
            Text(text).font(Typo.body(12, .semibold))
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(Palette.paper, in: Capsule())
    }
}

/// Round 44pt icon button with hairline border.
struct CircleIconButton: View {
    let systemImage: String
    let label: String
    var filled = false
    var badge = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(filled ? Palette.paper : Palette.ink)
                .frame(width: 44, height: 44)
                .background(filled ? Palette.ink : Palette.card, in: Circle())
                .overlay {
                    if !filled {
                        Circle().strokeBorder(Palette.borderButton, lineWidth: 1)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(Palette.orange)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: -11, y: 10)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Palette.accent
    var foreground: Color = .white
    var height: CGFloat = 48
    var radius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body(15, .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var foreground: Color = Palette.ink
    var height: CGFloat = 48
    var radius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body(15, .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Plain accent-coloured text link (e.g. "See all", "Change").
struct LinkButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .bold))
                }
                Text(title).font(Typo.body(14, .semibold))
            }
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selection controls

/// Two-option segmented control matching the design's pill segments.
struct SegmentedPill<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, label in
                let isOn = value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = value }
                } label: {
                    Text(label)
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(isOn ? Palette.ink : Palette.segmentOff)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Palette.ink.opacity(0.12), radius: 1, y: 1)
                                    .shadow(color: Palette.ink.opacity(0.06), radius: 4, y: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.segmentTrack, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Row of filter chips; the selected chip is filled ink.
struct FilterChips<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var scrolls = true

    var body: some View {
        if scrolls {
            ScrollView(.horizontal) {
                chips.padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        } else {
            chips
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { value, label in
                let isOn = value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = value }
                } label: {
                    Text(label)
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(isOn ? Palette.paper : Palette.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(isOn ? Palette.ink : Palette.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? Palette.ink : Palette.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Layout

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let addition = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += addition
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
