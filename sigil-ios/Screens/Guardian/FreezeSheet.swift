import SwiftUI

/// Freezing is per family, so a guardian with several dependents chooses who to
/// freeze and signs once for each. "Freeze everyone" is not one switch.
struct FreezeSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var working: String?

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
    }

    /// Freezing is signed, and the signature names the family, so the family has to be
    /// the selected one when it is sent.
    private func toggle(_ dependent: Dependent, frozen: Bool) async {
        working = dependent.familyID
        defer { working = nil }
        session.selectedFamilyID = dependent.familyID
        _ = await store.setFrozen(!frozen)
    }

    private func row(_ dependent: Dependent) -> some View {
        let frozen = store.families.first { $0.id == dependent.familyID }?.frozen ?? false

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
            if working == dependent.familyID {
                ProgressView().controlSize(.small)
            } else {
                Button(frozen ? "Unfreeze" : "Freeze") {
                    Task { await toggle(dependent, frozen: frozen) }
                }
                .font(Typo.body(14, .semibold))
                .foregroundStyle(frozen ? Palette.accent : Palette.danger)
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 60)
    }
}

#Preview {
    let session = AppSession()
    return Color.white.sheet(isPresented: .constant(true)) {
        FreezeSheet().environment(session).environment(Store(session: session))
    }
}
