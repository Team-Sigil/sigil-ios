import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var session
    @State private var role: Role = .guardian
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    private enum Field { case email, password }

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

    private var form: some View {
        VStack(spacing: 18) {
            SegmentedPill(
                options: [(Role.guardian, "Guardian"), (Role.dependent, "Dependent")],
                selection: $role
            )

            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Email")
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focused, equals: .email)
                        .onSubmit { focused = .password }
                        .modifier(InputFieldStyle())
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        fieldLabel("Password")
                        Spacer()
                        Button("Forgot password?") {}
                            .font(Typo.body(13, .medium))
                            .foregroundStyle(Palette.ink)
                    }
                    SecureField("Your password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focused, equals: .password)
                        .onSubmit { session.signIn(as: role) }
                        .modifier(InputFieldStyle())
                }
            }

            Button {
                session.signIn(as: role)
            } label: {
                HStack(spacing: 8) {
                    Text("Sign in as \(role == .guardian ? "guardian" : "dependent")")
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54))
            .contentTransition(.opacity)

            HStack(spacing: 4) {
                Text("New to Sigil?").foregroundStyle(Palette.textSecondary)
                Button("Create an account") {}
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
            }
            .font(Typo.body(14))
            .padding(.top, 4)
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

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Typo.body(13, .medium))
            .foregroundStyle(Palette.textSecondary)
    }
}

private struct InputFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Typo.body(16))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 1)
            )
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
