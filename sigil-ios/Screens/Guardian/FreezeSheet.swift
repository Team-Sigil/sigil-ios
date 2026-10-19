import SwiftUI

/// Freezing is per family, so a guardian with several dependents chooses who to
/// freeze and signs once for each. "Freeze everyone" is not one switch.
struct FreezeSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var signing: Dependent?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Freeze transfers")
                    .font(Typo.display(24))
                    .tracking(-0.4)
                    .accessibilityAddTraits(.isHeader)
                Text("A freeze stops everything for one dependent, whatever the agent decides. Each one needs its own signature.")
                    .font(Typo.body(15))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
            }

            ListCard {
                ForEach(MockData.dependents) { dependent in
                    row(dependent)
                }
            }

            Spacer(minLength: 0)

            Button("Done") { dismiss() }
                .buttonStyle(SecondaryButtonStyle(height: 50))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $signing) { dependent in
            SignatureSheet(
                title: session.isFrozen(dependent.familyID)
                    ? "Lift \(dependent.name)'s freeze"
                    : "Freeze \(dependent.name)",
                summary: session.isFrozen(dependent.familyID)
                    ? "The agent can send to \(dependent.name) again, inside the limits you signed."
                    : "Nothing reaches \(dependent.name) until you unfreeze. Your other dependents are unaffected.",
                message: [
                    "FinGuard:freeze",
                    "family:\(dependent.familyID)",
                    "frozen:\(session.isFrozen(dependent.familyID) ? "false" : "true")",
                    "nonce:\(MockData.nonce)",
                ],
                confirmTitle: session.isFrozen(dependent.familyID) ? "Sign and unfreeze" : "Sign and freeze"
            ) {
                withAnimation(.snappy) {
                    session.setFrozen(!session.isFrozen(dependent.familyID), familyID: dependent.familyID)
                }
            }
        }
    }

    private func row(_ dependent: Dependent) -> some View {
        let frozen = session.isFrozen(dependent.familyID)

        return HStack(spacing: 12) {
            Avatar(initials: dependent.initials, size: 36,
                   background: dependent.avatarBackground,
                   foreground: dependent.avatarForeground, fontSize: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text(dependent.name).font(Typo.body(15, .semibold))
                Text(frozen ? "Frozen" : "Agent active")
                    .font(Typo.body(12))
                    .foregroundStyle(frozen ? Palette.orangeInk : Palette.muted)
            }
            Spacer()
            Button(frozen ? "Unfreeze" : "Freeze") { signing = dependent }
                .font(Typo.body(14, .semibold))
                .foregroundStyle(frozen ? Palette.accent : Palette.danger)
                .buttonStyle(.plain)
        }
        .frame(minHeight: 60)
    }
}

/// `sheet(item:)` needs an identifiable selection; Dependent already is one.
private extension View {
    func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )) {
            if let value = item.wrappedValue {
                content(value)
            }
        }
    }
}

#Preview {
    Color.white.sheet(isPresented: .constant(true)) {
        FreezeSheet().environment(AppSession())
    }
}
