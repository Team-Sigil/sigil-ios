//
//  ContentView.swift
//  sigil-ios
//
//  Created by Han Win Aung on 16/10/2569 BE.
//

import SwiftUI

struct ContentView: View {
    @State private var session = AppSession()
    @State private var store: Store?

    var body: some View {
        Group {
            switch session.role {
            case nil:
                LoginView()
                    .transition(.opacity)
            case .guardian:
                // A guardian with no dependents has nothing to show yet, so the first
                // thing they do is register one.
                if session.familyIDs.isEmpty && session.signedIn {
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
        .environment(store ?? Store(session: session))
        .task {
            if store == nil { store = Store(session: session) }
            if let role = Role.fromLaunchArguments {
                session.signInOffline(as: role)
            } else {
                await session.restore()
                // `-signInNow` runs the real sign-in on launch, so the round-trip to the
                // gateway can be checked on the simulator, which cannot be tapped.
                if !session.signedIn,
                   ProcessInfo.processInfo.arguments.contains("-signInNow") {
                    await session.signIn()
                }
            }
            if session.signedIn { await store?.load() }
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
