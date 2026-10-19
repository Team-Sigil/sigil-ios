import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var session
    @Environment(Store.self) private var store
    @State private var role: Role = .guardian
    @State private var signingIn = false

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

    /// The card at the bottom. There is nothing to type: Phantom holds the key, tells the
    /// app which wallet is connected, and the gateway decides from that wallet whether
    /// this is a guardian or a dependent.
    private var form: some View {
        VStack(spacing: 18) {
            // Only ever shown with `-localWallet`, where there is no Phantom to connect to.
            if LocalWallet.isEnabled {
                SegmentedPill(
                    options: [(Role.guardian, "Guardian"), (Role.dependent, "Dependent")],
                    selection: $role
                )
            }

            Button {
                signIn()
            } label: {
                HStack(spacing: 8) {
                    if signingIn {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(buttonTitle)
                    if !signingIn {
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54))
            .contentTransition(.opacity)
            .disabled(signingIn)

            Text("No password. Your wallet signs you in, and whether you see the guardian or the dependent side follows from it.")
                .font(Typo.body(14))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            if let problem = session.signInProblem {
                Text(problem)
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if !LocalWallet.isEnabled, !Phantom.shared.isAvailable {
                Link(destination: URL(string: "https://phantom.app/download")!) {
                    HStack(spacing: 4) {
                        Text("Phantom isn't installed.").foregroundStyle(Palette.textSecondary)
                        Text("Get it").fontWeight(.semibold).foregroundStyle(Palette.ink)
                    }
                    .font(Typo.body(14))
                }
                .padding(.top, 4)
            }
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
    }

    private var buttonTitle: String {
        if signingIn { return "Waiting for your wallet\u{2026}" }
        if LocalWallet.isEnabled {
            return "Sign in as \(role == .guardian ? "guardian" : "dependent")"
        }
        return "Connect Phantom"
    }

    /// Signing in is a wallet signature over the gateway's own text — there is no
    /// password in Sigil (SEC-09), and the role comes back from the gateway rather than
    /// being chosen here: a wallet registered as someone's dependent is a dependent.
    private func signIn() {
        guard !signingIn else { return }
        Task {
            signingIn = true
            defer { signingIn = false }
            if LocalWallet.isEnabled {
                await session.signIn(as: role)
            } else {
                await session.signIn()
            }
            if session.signedIn { await store.load() }
        }
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
    let session = AppSession()
    LoginView()
        .environment(session)
        .environment(Store(session: session))
}
