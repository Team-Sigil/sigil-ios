import SwiftUI

/// Asking for money, in two taps: an amount and what it's for.
///
/// Deliberately not a chat. The dependent states the amount and the category, and
/// `message`, `amount_requested` and `emergency_claimed` are built from that, so the
/// engine gets an exact integer to cap the transfer with instead of a number parsed
/// out of prose.
struct AskSheet: View {
    let dependent: Dependent
    /// The signed limits and this week's budget, so the hint can say what will probably
    /// happen. The engine still decides.
    let limits: PolicyBody?
    let budget: Budget?
    /// Called with the finished ask; the caller owns what happens next.
    var onAsk: (Units, Category, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @State private var digits = ""
    @State private var category: Category?
    @State private var purpose = ""
    @State private var emergency = false
    @State private var showingAllCategories = false
    @FocusState private var amountFocused: Bool

    private var policy: PolicyBody? { limits }
    private var guardianName: String { store.guardianName }

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
                    purposeField
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
        .onAppear {
            // `-askCategory education` preselects a chip, so the filled sheet can be
            // checked on the simulator without tapping.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-askCategory"),
               let raw = arguments[safe: index + 1], let preset = Category(rawValue: raw) {
                category = preset
                purpose = preset.label
            }
        }
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
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("$")
                    .font(Typo.mono(40))
                    .foregroundStyle(amount > .zero ? Palette.ink : Palette.dashedChip)
                TextField("0", text: $digits)
                    .font(Typo.mono(52))
                    .tracking(-2)
                    .keyboardType(.numberPad)
                    .focused($amountFocused)
                    .fixedSize()
                    .onChange(of: digits) { _, new in
                        // Whole dollars only, so the amount is always an exact integer.
                        let cleaned = new.filter(\.isNumber).prefix(6)
                        if cleaned != new { digits = String(cleaned) }
                    }
                    .accessibilityLabel("Amount")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                ForEach([Int64(10), 20, 50], id: \.self) { quick in
                    Button {
                        withAnimation(.snappy) { digits = String(quick) }
                    } label: {
                        Text("$\(quick)")
                            .font(Typo.body(14, .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Palette.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { amountFocused = true }
    }

    // MARK: What for

    /// One field, not two: tapping a chip writes it into the box, and the box can
    /// then be edited into something more specific without losing the category.
    private var purposeField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "What for?")

            TextField("Tap one below, or type it", text: $purpose, axis: .vertical)
                .lineLimit(1...3)
                .font(Typo.body(17))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 54, alignment: .topLeading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(category == nil ? Palette.borderStrong : Palette.ink, lineWidth: 1))

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
        let isBlocked = policy?.blockedCategories.contains(option) ?? false

        return Button {
            withAnimation(.snappy) {
                category = option
                purpose = option.label
                amountFocused = false
            }
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
        guard let policy else {
            return "Your guardian hasn't set your policy yet, so I can't send anything."
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
        if let budget, amount > budget.remaining {
            return "You have \(budget.remaining.compact) left this week, so I may offer you less."
        }
        if amount >= policy.proofThreshold {
            return "Over \(policy.proofThreshold.compact), I'll send it first and then ask for the receipt."
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
                onAsk(amount, category ?? .other, purpose.trimmingCharacters(in: .whitespacesAndNewlines), emergency)
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

#Preview {
    let session = AppSession()
    Color.white.sheet(isPresented: .constant(true)) {
        AskSheet(
            dependent: MockData.dependents[0],
            limits: MockData.policy(for: "mt").body,
            budget: MockData.budget(for: "mt")
        ) { _, _, _, _ in }
        .environment(Store(session: session))
    }
}
