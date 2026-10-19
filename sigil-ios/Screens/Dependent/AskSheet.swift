import SwiftUI

/// Asking for money, in two taps: an amount and what it's for.
///
/// Deliberately not a chat. The dependent states the amount and the category, and
/// `message`, `amount_requested` and `emergency_claimed` are built from that, so the
/// engine gets an exact integer to cap the transfer with instead of a number parsed
/// out of prose.
struct AskSheet: View {
    let dependent: Dependent
    /// Called with the finished ask; the caller owns what happens next.
    var onAsk: (Units, Category, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    @State private var category: Category?
    @State private var note = ""
    @State private var emergency = false
    @State private var showingAllCategories = false
    @FocusState private var noteFocused: Bool

    private var policy: PolicyBody { MockData.policy(for: dependent.id).body }
    private var budget: Budget { MockData.budget(for: dependent.id) }
    private var guardianName: String { MockData.guardian.shortName }

    private var amount: Units {
        Units(Int64(digits) ?? 0)
    }

    private var canAsk: Bool {
        amount > .zero && category != nil
    }

    /// The five categories most asks fall into, with the rest behind "More".
    private var offeredCategories: [Category] {
        let common: [Category] = [.food, .transport, .education, .health, .clothing]
        guard showingAllCategories else { return common }
        return Category.blockable
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    amountField
                    categoryField
                    noteField
                    emergencyToggle
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Text("Ask for money")
                .font(Typo.display(22))
                .tracking(-0.3)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, 24)
        .padding(.trailing, 10)
        .padding(.top, 8)
    }

    // MARK: Amount

    private var amountField: some View {
        VStack(spacing: 14) {
            Text(amount > .zero ? amount.compact : "$0")
                .font(Typo.mono(52))
                .tracking(-2)
                .foregroundStyle(amount > .zero ? Palette.ink : Palette.dashedChip)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Amount \(amount.display)")

            HStack(spacing: 8) {
                ForEach([Int64(10), 20, 50], id: \.self) { quick in
                    Button {
                        withAnimation(.snappy) { digits = String(quick) }
                    } label: {
                        Text("$\(quick)")
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Palette.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Keypad(digits: $digits, keyHeight: 46)
        }
    }

    // MARK: Category

    private var categoryField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "What for?")
            FlowLayout(spacing: 8) {
                ForEach(offeredCategories) { option in
                    categoryChip(option)
                }
                if !showingAllCategories {
                    Button {
                        withAnimation(.snappy) { showingAllCategories = true }
                    } label: {
                        Text("More…")
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .overlay(Capsule().strokeBorder(Palette.dashedChip,
                                                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func categoryChip(_ option: Category) -> some View {
        let isOn = category == option
        let isBlocked = policy.blockedCategories.contains(option)

        return Button {
            withAnimation(.snappy) { category = option }
        } label: {
            HStack(spacing: 5) {
                if isBlocked {
                    Image(systemName: "hand.raised.fill").font(.system(size: 10, weight: .bold))
                }
                Text(option.label).font(Typo.body(14, .semibold))
            }
            .foregroundStyle(isOn ? Palette.paper : (isBlocked ? Palette.danger : Palette.ink))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(isOn ? Palette.ink : Palette.card, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Palette.ink : Palette.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Note, emergency, hint

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "What is it for? (optional)")
            TextField("lab supplies for Thursday", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .font(Typo.body(16))
                .focused($noteFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 52, alignment: .topLeading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 1))
        }
    }

    private var emergencyToggle: some View {
        Toggle(isOn: $emergency) {
            VStack(alignment: .leading, spacing: 2) {
                Text("It's an emergency").font(Typo.body(15, .semibold))
                Text("Goes straight to \(guardianName), checked twice. It doesn't lift your limits.")
                    .font(Typo.body(12))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(1)
            }
        }
        .tint(Palette.orange)
        .padding(14)
        .background(emergency ? Palette.orangeSoft : Palette.card,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(emergency ? Palette.orangeBorder : Palette.border, lineWidth: 1))
    }

    /// What will probably happen, from the limits the app already holds. A guess for
    /// the person's benefit — the engine still decides.
    private var hint: some View {
        HStack(alignment: .top, spacing: 10) {
            SigilMark(size: 20)
            Text(hintText)
                .font(Typo.body(13))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.graySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.snappy, value: hintText)
    }

    private var hintText: String {
        guard amount > .zero else {
            return "Tell me how much you need and what it's for."
        }
        if let category, policy.blockedCategories.contains(category) {
            return "\(category.label) is blocked in your policy, so I can't send this one."
        }
        if emergency {
            return "\(guardianName) will be asked straight away, with my recommendation."
        }
        if amount > policy.maxPerRequest {
            return "That's over your \(policy.maxPerRequest.compact) per-request limit, so \(guardianName) will be asked first."
        }
        if amount > budget.remaining {
            return "You have \(budget.remaining.compact) left this week, so I may offer you less."
        }
        if amount >= policy.proofThreshold {
            return "Over \(policy.proofThreshold.compact) needs a receipt — I'll ask for a photo."
        }
        return "Inside your limits, so this usually goes out straight away."
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.divider)
            hint
                .padding(.horizontal, 24)
                .padding(.top, 12)
            Button {
                onAsk(amount, category ?? .other, note.trimmingCharacters(in: .whitespacesAndNewlines), emergency)
                dismiss()
            } label: {
                Text(canAsk ? "Ask for \(amount.compact)" : "Ask for money")
            }
            .buttonStyle(PrimaryButtonStyle(fill: canAsk ? Palette.accent : Palette.dashedChip, height: 54))
            .disabled(!canAsk)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .background(Palette.paper)
    }
}

/// Whole-dollar keypad, so an ask needs no keyboard at all.
private struct Keypad: View {
    @Binding var digits: String
    var keyHeight: CGFloat = 52

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { key in
                if key.isEmpty {
                    Color.clear.frame(height: keyHeight)
                } else {
                    Button {
                        withAnimation(.snappy(duration: 0.12)) { press(key) }
                    } label: {
                        Group {
                            if key == "⌫" {
                                Image(systemName: "delete.left").font(.system(size: 18, weight: .medium))
                            } else {
                                Text(key).font(Typo.mono(22))
                            }
                        }
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: keyHeight)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(key == "⌫" ? "Delete" : key)
                }
            }
        }
    }

    private func press(_ key: String) {
        if key == "⌫" {
            digits = String(digits.dropLast())
        } else if digits.count < 6 {
            digits = digits == "0" ? key : digits + key
        }
    }
}

#Preview {
    Color.white.sheet(isPresented: .constant(true)) {
        AskSheet(dependent: MockData.dependents[0]) { _, _, _, _ in }
    }
}
