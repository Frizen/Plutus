import SwiftUI

struct RecordsView: View {
    @ObservedObject private var recordStore = ExpenseRecordStore.shared
    @EnvironmentObject private var settings: AppSettings
    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var showClearConfirm = false
    @State private var isExporting = false

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
                            showClearConfirm = true
                        }
                        .confirmationDialog("确认清空所有本地记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                            Button("清空", role: .destructive) { recordStore.clear() }
                            Button("取消", role: .cancel) {}
                        } message: {
                            Text("此操作不可撤销，飞书中的数据不受影响。")
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
                            Task { await exportCSV() }
                        } label: {
                            if isExporting {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .disabled(isExporting)
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

    private func exportCSV() async {
        isExporting = true
        defer { isExporting = false }

        let records = recordStore.records
        let url = await Task.detached(priority: .userInitiated) {
            generateCSV(from: records)
        }.value

        if let url {
            exportURL = url
            showExportSheet = true
        }
    }

    /// RFC 4180：所有字段用双引号包围，字段内的双引号转义为 ""，换行符替换为空格
    private func generateCSV(from records: [ExpenseRecord]) -> URL? {
        func escape(_ value: String) -> String {
            let safe = value
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(safe)\""
        }

        var rows: [String] = [
            [escape("日期"), escape("金额"), escape("商户"),
             escape("分类"), escape("备注"), escape("记账成员")].joined(separator: ",")
        ]
        for record in records {
            let row = [
                escape(record.displayDate),
                escape(String(format: "%.2f", record.amount)),
                escape(record.merchant),
                escape(record.category),
                escape(record.notes ?? ""),
                escape(record.userName)
            ].joined(separator: ",")
            rows.append(row)
        }
        let csv = rows.joined(separator: "\r\n")

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
        .environmentObject(AppSettings())
}
