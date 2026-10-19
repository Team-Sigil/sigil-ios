//
//  ContentView.swift
//  sigil-ios
//
//  Created by Han Win Aung on 16/10/2569 BE.
//

import SwiftUI

struct ContentView: View {
    @State private var session = AppSession()

    var body: some View {
        Group {
            switch session.role {
            case nil:
                LoginView()
                    .transition(.opacity)
            case .guardian:
                GuardianTabView()
                    .transition(.opacity)
            case .dependent:
                DependentTabView()
                    .transition(.opacity)
            }
        }
        .environment(session)
        .task {
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
