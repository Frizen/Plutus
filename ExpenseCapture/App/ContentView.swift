import SwiftUI

struct ContentView: View {
    @AppStorage("setup_wizard_completed") private var wizardCompleted = false

    var body: some View {
        TabView {
            RecordsView()
                .tabItem {
                    Label("记录", systemImage: "list.bullet")
                }

            SettingsView()
                .tabItem {
                    Label("配置", systemImage: "gearshape")
                }

            LogView()
                .tabItem {
                    Label("日志", systemImage: "terminal")
                }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !wizardCompleted },
            set: { if !$0 { wizardCompleted = true } }
        )) {
            SetupWizardView()
        }
    }
}

#Preview {
    ContentView()
}
