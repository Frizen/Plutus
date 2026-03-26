import SwiftUI
import UserNotifications

struct ContentView: View {
    var body: some View {
        TabView {
            SettingsView()
                .tabItem {
                    Label("配置", systemImage: "gearshape")
                }

            LogView()
                .tabItem {
                    Label("日志", systemImage: "terminal")
                }
        }
        .onAppear {
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}

#Preview {
    ContentView()
}
