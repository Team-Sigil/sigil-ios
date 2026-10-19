import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var session
    var body: some View {
        VStack(spacing: 0) {
            hero
            form
        }
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Palette.ink
                LoginOrbit()
                    .frame(width: 420, height: 420)
                    .offset(x: 150, y: -10)
            }
            .ignoresSafeArea()
        }
        .clipped()
        .preferredColorScheme(.light)
    }

    private var hero: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 10) {
                SigilMark(size: 32)
                Text("Sigil")
                    .font(Typo.display(22))
                    .tracking(-0.2)
            }
            .foregroundStyle(Palette.paper)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 10) {
                Text("Allowance,\non policy.")
                    .font(Typo.display(42))
                    .tracking(-1)
                    .lineSpacing(-4)
                    .foregroundStyle(Palette.paper)
                    .accessibilityAddTraits(.isHeader)
                Text("Set the rules once. Sigil’s agent handles every request.")
                    .font(Typo.body(15))
                    .foregroundStyle(Palette.mutedOnDark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 40)
    }

    /// Sign-In With Solana: no password anywhere. The wallet signs the gateway's text,
    /// and the gateway decides from the address whether this is a guardian or a dependent,
    /// so the app never picks a role.
    private var form: some View {
        VStack(spacing: 16) {
            Button {
                Task { await session.signIn() }
            } label: {
                HStack(spacing: 8) {
                    if session.busy {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Signing you in…")
                    } else {
                        Image(systemName: "wallet.pass").font(.system(size: 16, weight: .semibold))
                        Text("Continue with your wallet")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54))
            .disabled(session.busy)

            if let problem = session.problem {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.top, 2)
                    Text(problem).font(Typo.body(13)).lineSpacing(2)
                }
                .foregroundStyle(Palette.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    Palette.dangerSoft,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .transition(.opacity)
            }

            Text("Your wallet signs one line of text to prove it's you. Nothing moves without a signature, and Sigil never holds your money.")
                .font(Typo.body(12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Palette.paper)
                .ignoresSafeArea(edges: .bottom)
        )
        .foregroundStyle(Palette.ink)
        .animation(.snappy, value: session.problem)
    }
}

/// Orbit illustration with ticks, the big sigil and two satellites.
private struct LoginOrbit: View {
    var body: some View {
        ZStack {
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let ring = { (r: CGFloat) in
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
                let paper = Palette.paper
                context.stroke(ring(60), with: .color(paper.opacity(0.22)), lineWidth: 1.2)
                context.stroke(ring(100), with: .color(paper.opacity(0.14)), lineWidth: 1)
                context.stroke(ring(140), with: .color(paper.opacity(0.12)), lineWidth: 1)
                context.stroke(ring(182), with: .color(paper.opacity(0.10)), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))

                var ticks = Path()
                for step in 0..<12 {
                    let angle = Double(step) * .pi / 6
                    let inner = CGPoint(x: c.x + 140 * cos(angle), y: c.y + 140 * sin(angle))
                    let outer = CGPoint(x: c.x + 154 * cos(angle), y: c.y + 154 * sin(angle))
                    ticks.move(to: inner)
                    ticks.addLine(to: outer)
                }
                context.stroke(ticks, with: .color(paper.opacity(0.22)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

                context.fill(Path(ellipseIn: CGRect(x: 123.4 - 5, y: 160 - 5, width: 10, height: 10)), with: .color(Palette.accent))
                let satellite = Path(ellipseIn: CGRect(x: 296.6 - 4, y: 260 - 4, width: 8, height: 8))
                context.fill(satellite, with: .color(Palette.ink))
                context.stroke(satellite, with: .color(paper.opacity(0.6)), lineWidth: 1.2)
            }
            SigilMark(size: 96)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    LoginView().environment(AppSession())
}
