import SwiftUI

/// Freezing is per family, so a guardian with several dependents chooses who to
/// freeze and signs once for each. "Freeze everyone" is not one switch.
struct FreezeSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var signing: FreezeIntent?

    /// A freeze the guardian has chosen but not yet signed. The nonce is taken first, so
    /// the sheet can show the exact text the wallet will sign.
    private struct FreezeIntent: Identifiable {
        let dependent: Dependent
        let frozen: Bool
        let nonce: String
        var id: String { "\(dependent.familyID)-\(frozen)" }
    }

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
                ForEach(store.dependents) { dependent in
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
        .sheet(item: $signing) { intent in
            SignatureSheet(
                title: intent.frozen
                    ? "Freeze \(intent.dependent.name)"
                    : "Lift \(intent.dependent.name)'s freeze",
                summary: intent.frozen
                    ? "Nothing reaches \(intent.dependent.name) until you unfreeze. Your other dependents are unaffected."
                    : "The agent can send to \(intent.dependent.name) again, inside the limits you signed.",
                message: [
                    "FinGuard:freeze",
                    "family:\(intent.dependent.familyID)",
                    "frozen:\(intent.frozen)",
                    "nonce:\(intent.nonce)",
                ],
                confirmTitle: intent.frozen ? "Sign and freeze" : "Sign and unfreeze"
            ) {
                Task {
                    _ = await store.setFrozen(
                        intent.frozen, familyID: intent.dependent.familyID, nonce: intent.nonce
                    )
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
            Button(frozen ? "Unfreeze" : "Freeze") { prepare(dependent, frozen: !frozen) }
                .font(Typo.body(14, .semibold))
                .foregroundStyle(frozen ? Palette.accent : Palette.danger)
                .buttonStyle(.plain)
        }
        .frame(minHeight: 60)
    }

    private func prepare(_ dependent: Dependent, frozen: Bool) {
        Task {
            guard let nonce = await store.nonce(
                purpose: "freeze", family: dependent.familyID
            ) else { return }
            signing = FreezeIntent(dependent: dependent, frozen: frozen, nonce: nonce)
        }
    }
}

#Preview {
    let session = AppSession()
    Color.white.sheet(isPresented: .constant(true)) {
        FreezeSheet()
            .environment(session)
            .environment(Store(session: session))
    }
}
