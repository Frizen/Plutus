import SwiftUI
import AppIntents

@main
struct ExpenseCaptureApp: App {
    init() {
        // 更新 App Shortcuts 元数据（Siri / Spotlight 发现）
        ExpenseCaptureShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
