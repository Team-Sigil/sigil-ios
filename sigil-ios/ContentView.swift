//
//  ContentView.swift
//  sigil-ios
//
//  Created by Han Win Aung on 16/10/2569 BE.
//

import SwiftUI

/// The session and the store, created together so neither has to be optional.
@MainActor
final class AppBundle {
    let session = AppSession()
    let store: Store

    init() {
        store = Store(session: session)
    }
}

struct ContentView: View {
    @State private var bundle = AppBundle()
    @Environment(\.scenePhase) private var scenePhase

    private var session: AppSession { bundle.session }

    var body: some View {
        Group {
            switch session.role {
            case nil:
                LoginView()
                    .transition(.opacity)
            case .guardian:
                // A new guardian has no dependents yet, and nothing else can be set up
                // until one is registered with their wallet signature.
                if session.needsOnboarding {
                    OnboardingView()
                        .transition(.opacity)
                } else {
                    GuardianTabView()
                        .transition(.opacity)
                }
            case .dependent:
                DependentTabView()
                    .transition(.opacity)
            }
        }
        .environment(session)
        .environment(bundle.store)
        // Phantom comes back through sigil://onConnect and sigil://onSign.
        .onOpenURL { url in
            Phantom.shared.handle(url)
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the app without a reply means they left Phantom without
            // approving, so the waiting request is dropped rather than hanging.
            if phase == .active { Phantom.shared.appBecameActive() }
        }
        .task {
            await session.restore()
            // A launch argument wins over the stored session, so the simulator can be put
            // into either role without signing out by hand.
            if let role = Role.fromLaunchArguments, session.role != role {
                session.signOut()
                await session.signIn(as: role)
            }
            if session.signedIn { await bundle.store.load() }
        }
    }
}

extension Role {
    /// Opens the app straight into one role, so a screen can be checked on the
    /// simulator without going through sign-in. Only ever set by a launch argument:
    /// `xcrun simctl launch <device> <bundle id> -startAsDependent`.
    static var fromLaunchArguments: Role? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-startAsDependent") { return .dependent }
        if arguments.contains("-startAsGuardian") { return .guardian }
        return nil
    }
}

#Preview {
    ContentView()
}
