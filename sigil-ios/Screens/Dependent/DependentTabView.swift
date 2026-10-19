import SwiftUI

enum DependentTab: Hashable {
    case home, requests, policy, profile
}

struct DependentTabView: View {
    @Environment(Store.self) private var store
    @State private var tab: DependentTab = .home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: .home) {
                DependentHomeView(tab: $tab)
            }
            Tab("Requests", systemImage: "list.bullet.rectangle", value: .requests) {
                DependentRequestsView(tab: $tab)
            }
            Tab("Policy", systemImage: "checkmark.shield", value: .policy) {
                DependentPolicyView()
            }
            Tab("Profile", systemImage: "person", value: .profile) {
                DependentProfileView()
            }
        }
        .tint(Palette.ink)
        .preferredColorScheme(.light)
        .task {
            await store.load()
        }
        .onDisappear { store.stopListening() }
    }
}

#Preview {
    let session = AppSession()
    DependentTabView()
        .environment(session)
        .environment(Store(session: session))
}
