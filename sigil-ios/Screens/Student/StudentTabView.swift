import SwiftUI

enum StudentTab: Hashable {
    case home, requests, policy, profile
}

struct StudentTabView: View {
    @State private var tab: StudentTab = .home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: .home) {
                StudentHomeView(tab: $tab)
            }
            Tab("Requests", systemImage: "list.bullet.rectangle", value: .requests) {
                StudentRequestsView(tab: $tab)
            }
            Tab("Policy", systemImage: "checkmark.shield", value: .policy) {
                StudentPolicyView()
            }
            Tab("Profile", systemImage: "person", value: .profile) {
                StudentProfileView()
            }
        }
        .tint(Palette.ink)
        .preferredColorScheme(.light)
    }
}

#Preview {
    StudentTabView().environment(AppSession())
}
