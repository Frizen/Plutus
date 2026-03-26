import SwiftUI

// MARK: - Log Tab

struct LogView: View {
    @State private var logEntries: [LogEntry] = []

    var body: some View {
        NavigationStack {
            List {
                if logEntries.isEmpty {
                    ContentUnavailableView(
                        "暂无日志",
                        systemImage: "terminal",
                        description: Text("运行快捷指令后点击右上角刷新")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(logEntries.prefix(100)) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.level.rawValue)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.message)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Text(entry.timeString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string =
                                    "\(entry.timeString) \(entry.level.rawValue) \(entry.message)"
                            } label: {
                                Label("复制此条", systemImage: "doc.on.doc")
                            }
                        }
                    }

                    Button("清空日志", role: .destructive) {
                        IntentLogger.shared.clear()
                        logEntries = []
                    }
                }
            }
            .navigationTitle("日志")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 8) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // 复制全部
                    Button {
                        let all = logEntries.prefix(100)
                            .map { "\($0.timeString) \($0.level.rawValue) \($0.message)" }
                            .joined(separator: "\n")
                        UIPasteboard.general.string = all
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(logEntries.isEmpty)

                    // 刷新
                    Button {
                        logEntries = IntentLogger.shared.loadEntries()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                logEntries = IntentLogger.shared.loadEntries()
            }
        }
    }
}

#Preview {
    LogView()
}
