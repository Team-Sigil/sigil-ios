import SwiftUI

/// Confirmation for an action that is only valid as a guardian wallet signature.
///
/// Freezing, activating a policy and answering a question all travel to the engine
/// as signed messages, so the UI never presents them as a plain toggle or button —
/// the guardian sees the exact text their wallet will sign.
struct SignatureSheet: View {
    let title: String
    let summary: String
    /// The canonical message lines, shown verbatim so the guardian can read what they sign.
    let message: [String]
    let confirmTitle: String
    var onSign: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Typo.display(24))
                    .tracking(-0.4)
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(Typo.body(15))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Your wallet will sign")
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(message, id: \.self) { line in
                        Text(line)
                            .font(Typo.mono(13, .regular))
                            .foregroundStyle(Palette.paper)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(confirmTitle) {
                    onSign()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(height: 54))

                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle(height: 50))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color.white.sheet(isPresented: .constant(true)) {
        SignatureSheet(
            title: "Freeze all transfers",
            summary: "Nothing moves until you unfreeze, whatever the agent decides.",
            message: [
                "FinGuard:freeze",
                "family:8f2c…a91d",
                "frozen:true",
                "nonce:3c0b…77e4",
            ],
            confirmTitle: "Sign and freeze",
            onSign: {}
        )
    }
}
