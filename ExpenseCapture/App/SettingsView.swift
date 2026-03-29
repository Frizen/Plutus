import SwiftUI

// MARK: - Settings Tab

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var isTestingGLM = false
    @State private var isTestingFeishu = false
    @State private var glmTestResult: TestResult?
    @State private var feishuTestResult: TestResult?
    @State private var bitableURLInput: String = ""
    @State private var urlParseResult: TestResult?
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: 状态卡片
                Section {
                    statusCard
                }

                // MARK: GLM API
                Section {
                    SecureField("GLM API Key", text: $settings.glmAPIKey)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        Task { await testGLMConnection() }
                    } label: {
                        HStack {
                            if isTestingGLM {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "bolt.fill").foregroundStyle(.orange)
                            }
                            Text("测试 GLM 连接")
                        }
                    }
                    .disabled(settings.glmAPIKey.isEmpty || isTestingGLM)

                    if let result = glmTestResult { testResultRow(result) }
                } header: {
                    Label("智谱 GLM API", systemImage: "brain.head.profile")
                } footer: {
                    HStack(spacing: 4) {
                        Text("注册后即可免费使用。")
                        Link("去获取 API Key →",
                             destination: URL(string: "https://open.bigmodel.cn/usercenter/apikeys")!)
                            .foregroundStyle(Color.accentColor)
                    }
                    .font(.caption)
                }

                // MARK: 飞书同步开关
                Section {
                    Toggle(isOn: $settings.feishuSyncEnabled) {
                        Text("同步到飞书多维表格")
                    }
                } header: {
                    Label("数据同步", systemImage: "arrow.triangle.2.circlepath")
                } footer: {
                    Text(settings.feishuSyncEnabled
                         ? "记账数据将保存到本地，同时写入到飞书多维表格。"
                         : "记账数据仅保存到本地。")
                        .font(.caption)
                }

                // MARK: 飞书连接配置（仅开关开启时显示）
                if settings.feishuSyncEnabled {
                    Section {
                        LabeledTextField(label: "App ID",     placeholder: "cli_...", text: $settings.feishuAppID)
                        LabeledTextField(label: "App Secret", placeholder: "...",    text: $settings.feishuAppSecret, isSecure: true)

                        LabeledTextField(label: "表格链接", placeholder: "https://xxx.feishu.cn/base/...", text: $bitableURLInput)
                            .onChange(of: bitableURLInput) { _, newValue in
                                parseBitableURL(newValue)
                            }

                        if let result = urlParseResult { testResultRow(result) }

                        if !settings.bitableAppToken.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text("App Token: \(settings.bitableAppToken.prefix(12))…  Table ID: \(settings.tableID.prefix(12))…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            Task { await testFeishuConnection() }
                        } label: {
                            HStack {
                                if isTestingFeishu {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "bolt.fill").foregroundStyle(.blue)
                                }
                                Text("测试飞书连接")
                            }
                        }
                        .disabled(!settings.isFeishuConfigured || isTestingFeishu)

                        if let result = feishuTestResult { testResultRow(result) }
                    } header: {
                        Text("飞书连接配置")
                            .font(.caption)
                            .fontWeight(.regular)
                    }

                    // MARK: 记账成员
                    Section {
                        TextField("填入名字用于多人协同记账。个人记账可不填。", text: $settings.userName)
                    } header: {
                        Text("配置记账成员名")
                            .font(.caption)
                            .fontWeight(.regular)
                    }

                    // MARK: 字段名映射
                    Section {
                        LabeledTextField(label: "金额", placeholder: "金额", text: $settings.fieldAmount)
                        LabeledTextField(label: "商户", placeholder: "商户", text: $settings.fieldMerchant)
                        LabeledTextField(label: "日期", placeholder: "日期", text: $settings.fieldDate)
                        LabeledTextField(label: "备注", placeholder: "备注", text: $settings.fieldNotes)
                        if !settings.userName.isEmpty {
                            LabeledTextField(label: "记账成员", placeholder: "记账成员", text: $settings.fieldUserName)
                        }
                    } header: {
                        Text("字段名映射（建议保持默认值，如需修改请注意字段名和多维表格的列名一致）")
                            .font(.caption)
                            .fontWeight(.regular)
                    }
                }

                // MARK: Action Button 引导
                Section {
                    actionButtonGuide
                } header: {
                    Label("Action Button 配置", systemImage: "record.circle")
                }

                // MARK: 配置向导
                Section {
                    Button {
                        UserDefaults.standard.set(false, forKey: "setup_wizard_completed")
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("重新运行配置向导")
                        }
                    }
                }

                // MARK: 重置
                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("清除所有配置与记录")
                        }
                    }
                }
            }
            .navigationTitle("配置")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 8) }
            .environment(\.defaultMinListHeaderHeight, 32)
            .onAppear {
                // 若已有 token+tableID，回填链接输入框供用户查看
                if !settings.bitableAppToken.isEmpty && !settings.tableID.isEmpty {
                    bitableURLInput = "https://feishu.cn/base/\(settings.bitableAppToken)?table=\(settings.tableID)"
                }
            }
            .confirmationDialog("确认清除所有配置和本地记录？", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("清除", role: .destructive) { resetAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作不可撤销，飞书中的数据不受影响。")
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 16) {
            statusBadge(icon: "brain.head.profile", label: "GLM", isOK: settings.isGLMConfigured, color: .orange)
            Divider().frame(height: 40)
            modeStatusBadge
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var modeStatusBadge: some View {
        if settings.isFullyConfigured {
            statusBadge(icon: "icloud.fill",   label: "云同步", isOK: true,  color: .green)
        } else if settings.isGLMConfigured {
            statusBadge(icon: "internaldrive", label: "本地",   isOK: true,  color: .green)
        } else {
            statusBadge(icon: "xmark.circle",  label: "未就绪", isOK: false, color: .red)
        }
    }

    private func statusBadge(icon: String, label: String, isOK: Bool, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isOK ? color : .secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(isOK ? .primary : .secondary)
            Circle()
                .fill(isOK ? Color.green : Color.red)
                .frame(width: 8, height: 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Button Guide

    private let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/925b64d4982e4559a061f8bfb920913d")!

    private var actionButtonGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Link(destination: shortcutURL) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("获取快捷指令")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            ForEach(Array(guideSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.accentColor))
                    Text(step)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private let guideSteps = [
        "点击上方「获取快捷指令」，在快捷指令 App 中完成添加",
        "进入「设置 → 操作按钮」→ 选择「快捷指令」→ 选择「立即记账」"
    ]

    // MARK: - Test Helpers

    /// 代理给 AppSettings.parseBitableURL，更新本地 urlParseResult
    private func parseBitableURL(_ urlString: String) {
        guard let result = settings.parseBitableURL(urlString) else {
            urlParseResult = nil
            return
        }
        urlParseResult = TestResult(success: result.success, message: result.message)
    }

    private func testGLMConnection() async {
        isTestingGLM = true
        glmTestResult = nil
        defer { isTestingGLM = false }

        let key = settings.glmAPIKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            glmTestResult = TestResult(success: false, message: "API Key 不能为空")
            return
        }

        var request = URLRequest(url: URL(string: "https://open.bigmodel.cn/api/paas/v4/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    glmTestResult = TestResult(success: true, message: "GLM API Key 有效 ✓")
                } else if http.statusCode == 401 {
                    glmTestResult = TestResult(success: false, message: "API Key 无效，请检查")
                } else {
                    glmTestResult = TestResult(success: true, message: "已连接 (状态码 \(http.statusCode))")
                }
            }
        } catch {
            glmTestResult = TestResult(success: false, message: "连接失败: \(error.localizedDescription)")
        }
    }

    private func testFeishuConnection() async {
        isTestingFeishu = true
        feishuTestResult = nil
        defer { isTestingFeishu = false }

        let service = FeishuBitableService.shared
        do {
            let message = try await service.testConnection(
                appID: settings.feishuAppID,
                appSecret: settings.feishuAppSecret,
                appToken: settings.bitableAppToken,
                tableID: settings.tableID
            )
            feishuTestResult = TestResult(success: true, message: message)
        } catch {
            feishuTestResult = TestResult(success: false, message: error.localizedDescription)
        }
    }

    private func testResultRow(_ result: TestResult) -> some View {
        HStack {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? .green : .red)
            Text(result.message)
                .font(.caption)
                .foregroundStyle(result.success ? .green : .red)
        }
    }

    @MainActor
    private func resetAll() {
        settings.glmAPIKey = ""
        settings.userName = ""
        settings.feishuSyncEnabled = false
        settings.feishuAppID = ""
        settings.feishuAppSecret = ""
        settings.bitableAppToken = ""
        settings.tableID = ""
        settings.fieldAmount = "金额"
        settings.fieldMerchant = "商户"
        settings.fieldDate = "日期"
        settings.fieldNotes = "备注"
        settings.fieldUserName = "记账成员"
        bitableURLInput = ""
        urlParseResult = nil

        ExpenseRecordStore.shared.clear()
        IntentLogger.shared.clear()
    }
}

// MARK: - Shared Supporting Views

struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                TextField(placeholder, text: $text)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
    }
}

struct ExpenseRecordRow: View {
    let record: ExpenseRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: categoryIcon(record.category))
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(categoryColor(record.category)))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.merchant)
                    .font(.subheadline).fontWeight(.medium)
                Text("\(record.category) · \(record.displayDate)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text(record.displayAmount)
                .font(.subheadline).fontWeight(.semibold)
        }
        .padding(.vertical, 2)
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "外出就餐", "外卖", "水果", "零食", "买菜", "奶茶", "饮料酒水":
            return "fork.knife"
        case "地铁公交", "长途交通", "打车":
            return "car.fill"
        case "生活用品", "电子数码", "美妆护肤", "衣裤鞋帽", "书报杂志", "珠宝首饰", "宠物", "美发":
            return "bag.fill"
        case "娱乐", "旅游", "按摩", "运动":
            return "gamecontroller.fill"
        case "医疗", "药物":
            return "cross.fill"
        case "物业费", "水电燃气", "电器", "手机话费":
            return "house.fill"
        case "红包", "礼物":
            return "gift.fill"
        case "慈善":
            return "heart.fill"
        case "保险":
            return "shield.fill"
        default:
            return "creditcard.fill"
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "外出就餐", "外卖", "水果", "零食", "买菜", "奶茶", "饮料酒水":
            return .orange
        case "地铁公交", "长途交通", "打车":
            return .blue
        case "生活用品", "电子数码", "美妆护肤", "衣裤鞋帽", "书报杂志", "珠宝首饰", "宠物", "美发":
            return .purple
        case "娱乐", "旅游", "按摩", "运动":
            return .pink
        case "医疗", "药物":
            return .red
        case "物业费", "水电燃气", "电器", "手机话费":
            return .teal
        case "红包", "礼物":
            return .yellow
        case "慈善":
            return .green
        case "保险":
            return .indigo
        default:
            return .gray
        }
    }
}

struct TestResult {
    let success: Bool
    let message: String
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
