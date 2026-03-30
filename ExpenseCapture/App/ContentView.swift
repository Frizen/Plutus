import SwiftUI

struct ContentView: View {
    @AppStorage(AppSettings.wizardCompletedKey) private var wizardCompleted = false
    @StateObject private var settings = AppSettings.shared

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
        .environmentObject(settings)
        .fullScreenCover(isPresented: Binding(
            get: { !wizardCompleted },
            set: { if !$0 { wizardCompleted = true } }
        )) {
            SetupWizardView()
                .environmentObject(settings)
        }
    }
}

#Preview {
    ContentView()
}
