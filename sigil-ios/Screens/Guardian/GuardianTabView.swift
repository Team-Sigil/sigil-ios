import SwiftUI

enum GuardianTab: Hashable {
    case home, dependents, policies, activity, settings
}

struct GuardianTabView: View {
    @State private var tab: GuardianTab = .home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: .home) {
                ParentHomeView(tab: $tab)
            }
            Tab("Dependents", systemImage: "person.2", value: .dependents) {
                ParentDependentsView(tab: $tab)
            }
            Tab("Policies", systemImage: "checkmark.shield", value: .policies) {
                ParentPoliciesView()
            }
            Tab("Activity", systemImage: "waveform.path.ecg", value: .activity) {
                ParentActivityView()
            }
            Tab("Settings", systemImage: "slider.horizontal.3", value: .settings) {
                ParentSettingsView()
            }
        }
        .tint(Palette.ink)
        .preferredColorScheme(.light)
    }
}

#Preview {
    GuardianTabView().environment(AppSession())
}
