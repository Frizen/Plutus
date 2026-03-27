import SwiftUI

// MARK: - Settings Tab

struct SettingsView: View {
    @StateObject private var settings = AppSettings()

    @State private var isTestingGLM = false
    @State private var isTestingFeishu = false
    @State private var glmTestResult: TestResult?
    @State private var feishuTestResult: TestResult?
    @State private var feishuExpanded = false
    @State private var isCreatingTable = false
    @State private var createTableResult: TestResult?

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
                        Text("免费注册即送额度，够日常使用。")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("去获取 API Key →",
                             destination: URL(string: "https://open.bigmodel.cn/usercenter/apikeys")!)
                            .font(.caption)
                    }
                }

                // MARK: 飞书
                Section {
                    DisclosureGroup(isExpanded: $feishuExpanded) {
                        LabeledTextField(label: "App ID",     placeholder: "cli_...", text: $settings.feishuAppID)
                        LabeledTextField(label: "App Secret", placeholder: "...",    text: $settings.feishuAppSecret, isSecure: true)

                        // 一键建表：填了 ID+Secret 但还没有 App Token 时显示
                        if !settings.feishuAppID.isEmpty && !settings.feishuAppSecret.isEmpty
                            && settings.bitableAppToken.isEmpty {
                            Button {
                                Task { await createExpenseTable() }
                            } label: {
                                HStack {
                                    if isCreatingTable {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "wand.and.stars").foregroundStyle(.blue)
                                    }
                                    Text("一键创建记账表格")
                                }
                            }
                            .disabled(isCreatingTable)

                            if let result = createTableResult { testResultRow(result) }
                        }

                        LabeledTextField(label: "App Token",  placeholder: "...",    text: $settings.bitableAppToken)
                        LabeledTextField(label: "Table ID",   placeholder: "tbl...", text: $settings.tableID)

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
                    } label: {
                        Text("可选，展开配置云端同步")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("飞书 Bitable", systemImage: "tablecells")
                } footer: {
                    Text("「一键建表」需在飞书开放平台为应用开通 drive:drive 权限。")
                        .font(.caption)
                }

                // MARK: 字段名映射
                Section {
                    LabeledTextField(label: "金额",     placeholder: "金额",     text: $settings.fieldAmount)
                    LabeledTextField(label: "一级分类", placeholder: "一级分类", text: $settings.fieldPrimaryCategory)
                    LabeledTextField(label: "二级分类", placeholder: "二级分类", text: $settings.fieldSubCategory)
                    LabeledTextField(label: "商户",     placeholder: "商户",     text: $settings.fieldMerchant)
                    LabeledTextField(label: "日期",     placeholder: "日期",     text: $settings.fieldDate)
                    LabeledTextField(label: "备注",     placeholder: "备注",     text: $settings.fieldNotes)
                } header: {
                    Label("字段名映射（需与表格完全一致）", systemImage: "list.bullet.rectangle")
                } footer: {
                    Text("若飞书写入报错 FieldNameNotFound，请检查字段名是否与多维表格列名完全匹配。")
                        .font(.caption)
                }

                // MARK: Action Button 引导
                Section {
                    actionButtonGuide
                } header: {
                    Label("Action Button 配置", systemImage: "record.circle")
                }
            }
            .navigationTitle("配置")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 8) }
            .onAppear { feishuExpanded = settings.isFeishuConfigured }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 16) {
            statusBadge(icon: "brain.head.profile", label: "GLM",  isOK: settings.isGLMConfigured,   color: .orange)
            Divider().frame(height: 40)
            statusBadge(icon: "tablecells",         label: "飞书", isOK: settings.isFeishuConfigured, color: .blue)
            Divider().frame(height: 40)
            modeStatusBadge
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var modeStatusBadge: some View {
        if settings.isFullyConfigured {
            statusBadge(icon: "icloud.fill",      label: "云同步", isOK: true, color: .green)
        } else if settings.isGLMConfigured {
            statusBadge(icon: "internaldrive",    label: "本地",   isOK: true, color: .green)
        } else {
            statusBadge(icon: "xmark.circle",     label: "未就绪", isOK: false, color: .red)
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

    private var actionButtonGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("按以下步骤配置 Action Button：")
                .font(.subheadline).fontWeight(.medium)
            ForEach(Array(guideSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.accentColor))
                    Text(step)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private let guideSteps = [
        "打开「快捷指令」App → 点击右上角 + 新建快捷指令",
        "添加动作：搜索「截屏」并添加",
        "继续添加动作：搜索「记录一笔消费」（本 App 提供）→ 长按截图栏右侧的 ⊕ 图标 → 在弹出菜单中选择「截屏」变量（而非选择本地文件）",
        "保存快捷指令，命名为「立即记账」",
        "进入「设置 → 操作按钮」→ 选择「快捷指令」→ 选择「立即记账」"
    ]

    // MARK: - Test Helpers

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

        let service = FeishuBitableService()
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

    private func createExpenseTable() async {
        isCreatingTable = true
        createTableResult = nil
        defer { isCreatingTable = false }

        let service = FeishuBitableService()
        do {
            let result = try await service.createExpenseTable(
                appID: settings.feishuAppID,
                appSecret: settings.feishuAppSecret
            )
            settings.bitableAppToken = result.appToken
            settings.tableID = result.tableID
            createTableResult = TestResult(success: true, message: "表格创建成功 ✓ 已自动填入 Token 和 Table ID")
            feishuExpanded = true
        } catch {
            createTableResult = TestResult(success: false, message: "创建失败: \(error.localizedDescription)")
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
            Image(systemName: categoryIcon(record))
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(categoryColor(record)))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.merchant)
                    .font(.subheadline).fontWeight(.medium)
                Text("\(record.primaryCategory) · \(record.subCategory) · \(record.displayDate)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text(record.displayAmount)
                .font(.subheadline).fontWeight(.semibold)
        }
        .padding(.vertical, 2)
    }

    private func categoryIcon(_ record: ExpenseRecord) -> String {
        switch record.primaryCategory {
        case "餐饮":    return "fork.knife"
        case "行车交通": return "car.fill"
        case "购物消费": return "bag.fill"
        case "休闲娱乐": return "gamecontroller.fill"
        case "医疗":    return "cross.fill"
        case "居家生活": return "house.fill"
        case "人情费用": return "gift.fill"
        case "公益":    return "heart.fill"
        case "保险":    return "shield.fill"
        default:       return "creditcard.fill"
        }
    }

    private func categoryColor(_ record: ExpenseRecord) -> Color {
        switch record.primaryCategory {
        case "餐饮":    return .orange
        case "行车交通": return .blue
        case "购物消费": return .purple
        case "休闲娱乐": return .pink
        case "医疗":    return .red
        case "居家生活": return .teal
        case "人情费用": return .yellow
        case "公益":    return .green
        case "保险":    return .indigo
        default:       return .gray
        }
    }
}

struct TestResult {
    let success: Bool
    let message: String
}

#Preview {
    SettingsView()
}
