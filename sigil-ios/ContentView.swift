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
    }
}

#Preview {
    ContentView()
}
