import SwiftUI

struct RecordsView: View {
    @StateObject private var recordStore = ExpenseRecordStore()
    @StateObject private var settings = AppSettings()

    var body: some View {
        NavigationStack {
            Group {
                if recordStore.records.isEmpty {
                    ContentUnavailableView(
                        "暂无记录",
                        systemImage: "tray",
                        description: Text("使用 Action Button 截屏后将自动记录消费")
                    )
                } else {
                    List {
                        ForEach(recordStore.records.prefix(100)) { record in
                            ExpenseRecordRow(record: record)
                        }
                        Button("清空记录", role: .destructive) {
                            recordStore.clear()
                        }
                    }
                }
            }
            .navigationTitle("最近记录")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 8) }
            .toolbar {
                if !settings.bitableAppToken.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Link(destination: URL(string: "https://feishu.cn/base/\(settings.bitableAppToken)?table=\(settings.tableID)")!) {
                            Label("查看全部", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    RecordsView()
}
