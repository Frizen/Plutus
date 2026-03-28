import SwiftUI

struct RecordsView: View {
    @ObservedObject private var recordStore = ExpenseRecordStore.shared
    @StateObject private var settings = AppSettings()
    @State private var showExportSheet = false
    @State private var exportURL: URL?

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
                        ForEach(recordStore.records) { record in
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
            .onAppear { recordStore.reload() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // 导出 CSV
                    if !recordStore.records.isEmpty {
                        Button {
                            exportURL = generateCSV()
                            if exportURL != nil { showExportSheet = true }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    // 跳转飞书（仅同步开启且表格链接解析成功时显示）
                    if settings.isFeishuSyncActive,
                       let url = feishuURL {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let url = exportURL {
                    ShareSheet(url: url)
                }
            }
        }
    }

    private var feishuURL: URL? {
        guard !settings.bitableAppToken.isEmpty, !settings.tableID.isEmpty else { return nil }
        return URL(string: "https://feishu.cn/base/\(settings.bitableAppToken)?table=\(settings.tableID)")
    }

    private func generateCSV() -> URL? {
        var rows: [String] = ["日期,金额,商户,分类,备注,记账成员"]
        for record in recordStore.records {
            let date = record.displayDate.replacingOccurrences(of: ",", with: " ")
            let merchant = record.merchant.replacingOccurrences(of: ",", with: " ")
            let category = record.category.replacingOccurrences(of: ",", with: " ")
            let notes = (record.notes ?? "").replacingOccurrences(of: ",", with: " ")
            let user = record.userName.replacingOccurrences(of: ",", with: " ")
            rows.append("\(date),\(record.amount),\(merchant),\(category),\(notes),\(user)")
        }
        let csv = rows.joined(separator: "\n")

        let filename = "plutus_records_\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    RecordsView()
}
