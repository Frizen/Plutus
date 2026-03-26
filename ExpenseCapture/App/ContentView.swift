import SwiftUI

struct ContentView: View {
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
    }
}

#Preview {
    ContentView()
}
