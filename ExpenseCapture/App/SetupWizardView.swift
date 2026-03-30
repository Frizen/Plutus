import SwiftUI

// MARK: - Setup Wizard Root

struct SetupWizardView: View {
    @AppStorage("setup_wizard_completed") private var wizardCompleted = false
    @EnvironmentObject private var settings: AppSettings

    /// 导航历史栈，初始含 Welcome 页（页码 0）
    @State private var stack: [Int] = [0]

    // MARK: 拖拽返回
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingHorizontally = false

    // MARK: 前进动画
    @State private var pushingOutPage: Int? = nil
    @State private var incomingOffset: CGFloat = 0

    // MARK: 屏幕宽度（由 GeometryReader 写入，供手势和动画使用）
    @State private var screenWidth: CGFloat = 390

    private var isPushAnimating: Bool { pushingOutPage != nil }

    // MARK: 动画时长常量
    private let pushDuration: TimeInterval = 0.35
    private let popDuration:  TimeInterval = 0.28

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            VStack(spacing: 0) {
                // 进度点：固定在顶部，不参与滑动
                ProgressDots(current: stack.last ?? 0, total: 5)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                ZStack {                    // ── 下层：拖拽返回时的视差页（只在拖拽过程中渲染）
                    if stack.count >= 2, !isPushAnimating, dragOffset > 0 {
                        pageContent(for: stack[stack.count - 2])
                            .offset(x: -W * 0.25 + dragOffset * 0.25)
                            .allowsHitTesting(false)
                    }

                    // ── 中层：push 动画时被推走的旧页（滑向左侧）
                    if let outPage = pushingOutPage {
                        pageContent(for: outPage)
                            .offset(x: incomingOffset * 0.25 - W * 0.25)
                            .allowsHitTesting(false)
                    }

                    // ── 上层：当前页
                    pageContent(for: stack.last ?? 0)
                        .offset(x: isPushAnimating ? incomingOffset : dragOffset)
                        .allowsHitTesting(!isPushAnimating)
                }
                .simultaneousGesture(swipeBackGesture(W: W))
            }
            .onAppear { screenWidth = W }
            .onChange(of: W) { _, newW in screenWidth = newW }
        }
    }

    // MARK: - 右滑返回手势

    private func swipeBackGesture(W: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isPushAnimating, stack.count > 1 else { return }
                if !isDraggingHorizontally {
                    guard value.translation.width > 0,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    isDraggingHorizontally = true
                }
                dragOffset = max(0, value.translation.width)
            }
            .onEnded { value in
                guard isDraggingHorizontally else { return }
                isDraggingHorizontally = false
                let shouldPop = value.translation.width > W * 0.35 ||
                                value.predictedEndTranslation.width > W * 0.55
                if shouldPop {
                    withAnimation(.spring(response: popDuration, dampingFraction: 0.86)) {
                        dragOffset = W
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + popDuration) {
                        stack.removeLast()
                        dragOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: popDuration, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - 前进

    private func advance() {
        guard !isPushAnimating else { return }
        let current = stack.last ?? 0
        let next = (current == 2 && !settings.feishuSyncEnabled) ? 4 : current + 1
        pushingOutPage = current
        incomingOffset = screenWidth
        stack.append(next)
        withAnimation(.spring(response: pushDuration, dampingFraction: 0.9)) {
            incomingOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pushDuration + 0.05) {
            pushingOutPage = nil
        }
    }

    // MARK: - 页面路由

    @ViewBuilder
    private func pageContent(for page: Int) -> some View {
        switch page {
        case 0: WizardWelcomePage(onNext: advance)
        case 1: WizardGLMPage(settings: settings, onNext: advance)
        case 2: WizardFeishuPage(settings: settings, onNext: advance)
        case 3: WizardMemberPage(settings: settings, onNext: advance)
        default: WizardActionButtonPage(onDone: { wizardCompleted = true })
        }
    }
}

// MARK: - Progress Dots

private struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == current ? 10 : 7, height: index == current ? 10 : 7)
                    .animation(.easeInOut, value: current)
            }
        }
    }
}

// MARK: - Page Container

private struct WizardPageContainer<Content: View, BottomContent: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let bottomContent: () -> BottomContent

    var body: some View {
        VStack(spacing: 0) {
            // 内容区：顶部对齐，可滚动
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }

            // 底部按钮：固定在底部
            VStack(spacing: 10) {
                bottomContent()
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Page 0: Welcome

private struct WizardWelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        WizardPageContainer {
            VStack(alignment: .center, spacing: 20) {
                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                Text("欢迎使用 Plutus")
                    .font(.title).bold()
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("用 Action Button 拍一下截图，自动识别消费信息并记录到飞书多维表格。\n\n接下来只需几步配置即可开始使用。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } bottomContent: {
            Button("开始配置") { onNext() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

// MARK: - Page 1: GLM API Key

private enum GLMKeyMode {
    case unselected
    case testKey
    case ownKey
}

// 测试 Key 仅在此处维护，不对用户展示
private let kGLMTestAPIKey = "ae1e3046ccf8480ca4203a15b414ddf3.SMSoebc6IWpbrZIc"

private struct WizardGLMPage: View {
    @ObservedObject var settings: AppSettings
    let onNext: () -> Void

    @State private var keyMode: GLMKeyMode = .unselected
    @State private var isTestingGLM = false
    @State private var glmTestResult: WizardTestResult?

    private var canProceed: Bool {
        switch keyMode {
        case .unselected: return false
        case .testKey:    return true
        case .ownKey:     return !settings.glmAPIKey.isEmpty
        }
    }

    var body: some View {
        WizardPageContainer {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .frame(width: 80, height: 80)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("配置 GLM API Key")
                .font(.title).bold()
                .frame(maxWidth: .infinity, alignment: .center)

            Text("Plutus 使用智谱 GLM Vision 识别截图中的消费信息。")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                keyModeButton(
                    selected: keyMode == .testKey,
                    icon: "sparkles",
                    title: "使用测试 API Key",
                    subtitle: "无需注册，额度有限，适合体验"
                ) {
                    keyMode = .testKey
                    settings.glmAPIKey = kGLMTestAPIKey
                    glmTestResult = nil
                }

                keyModeButton(
                    selected: keyMode == .ownKey,
                    icon: "key.fill",
                    title: "使用我自己的 API Key",
                    subtitle: "注册智谱 AI 后免费获取，无额度限制"
                ) {
                    if keyMode == .testKey { settings.glmAPIKey = "" }
                    keyMode = .ownKey
                    glmTestResult = nil
                }
            }

            if keyMode == .testKey {
                // warning bar 全宽铺满
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("测试 Key 有每日调用额度限制，正式使用建议换成自己的 Key。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if keyMode == .ownKey {
                VStack(spacing: 12) {
                    SecureField("粘贴你的 GLM API Key", text: $settings.glmAPIKey)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let result = glmTestResult {
                        wizardTestResultRow(result)
                    }

                    // footer 样式：普通文字 + 独立可点链接
                    HStack(spacing: 4) {
                        Text("注册后即可免费使用，")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("去获取 API Key",
                             destination: URL(string: "https://open.bigmodel.cn/usercenter/apikeys")!)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        } bottomContent: {
            Button {
                Task { await handleNext() }
            } label: {
                HStack(spacing: 8) {
                    if isTestingGLM {
                        ProgressView().scaleEffect(0.8).tint(.white)
                    }
                    Text("下一步")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canProceed || isTestingGLM)
        }
        .onAppear {
            // 右滑返回时恢复已选择的 keyMode
            if keyMode == .unselected {
                if settings.glmAPIKey == kGLMTestAPIKey {
                    keyMode = .testKey
                } else if !settings.glmAPIKey.isEmpty {
                    keyMode = .ownKey
                }
            }
        }
    }

    private func keyModeButton(
        selected: Bool, icon: String, title: String, subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).fontWeight(.medium).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            )
        }
        .buttonStyle(.plain)
    }

    private func handleNext() async {
        // 只有自有 Key 模式需要在线验证
        guard keyMode == .ownKey else { onNext(); return }
        isTestingGLM = true
        glmTestResult = nil
        defer { isTestingGLM = false }

        let key = settings.glmAPIKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            glmTestResult = WizardTestResult(success: false, message: "API Key 不能为空")
            return
        }
        var request = URLRequest(url: URL(string: "https://open.bigmodel.cn/api/paas/v4/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                glmTestResult = WizardTestResult(success: false, message: "无法获取服务器响应")
                return
            }
            if http.statusCode == 200 {
                onNext()
            } else if http.statusCode == 401 {
                glmTestResult = WizardTestResult(success: false, message: "API Key 无效，请检查")
            } else {
                // 其他非 401 状态视为可用
                onNext()
            }
        } catch {
            glmTestResult = WizardTestResult(success: false, message: "连接失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - Page 2: Feishu Sync (原第 3 步，现提前至第 2 步)

private enum FeishuDocMode {
    case unselected
    case testDoc
    case ownDoc
}

// 测试飞书应用凭证，不对用户展示
private let kFeishuTestAppID     = "cli_a94fae2862ba9bc6"
private let kFeishuTestAppSecret = "oDdV4BA4ZqNZXHpxmfMsufLpJwHa0F7S"

private struct WizardFeishuPage: View {
    @ObservedObject var settings: AppSettings
    let onNext: () -> Void

    // MARK: - 状态结构体（替代 7 个独立 @State）

    private struct FeishuSetupState {
        var docMode: FeishuDocMode = .unselected
        var isCreatingDoc = false
        var createDocResult: WizardTestResult? = nil
        var bitableURLInput: String = ""
        var urlParseResult: WizardTestResult? = nil
        var isTestingFeishu = false
        var feishuTestResult: WizardTestResult? = nil

        mutating func resetOnToggleOff() {
            docMode = .unselected
            createDocResult = nil
            feishuTestResult = nil
        }

        mutating func switchToTestDoc() {
            urlParseResult = nil
            feishuTestResult = nil
            createDocResult = nil
            docMode = .testDoc
        }

        mutating func switchToOwnDoc() {
            createDocResult = nil
            feishuTestResult = nil
            docMode = .ownDoc
        }
    }

    @State private var state = FeishuSetupState()

    private var canProceed: Bool {
        guard settings.feishuSyncEnabled else { return true }
        switch state.docMode {
        case .unselected: return false
        case .testDoc:    return state.createDocResult?.success == true
        case .ownDoc:
            return !settings.feishuAppID.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !settings.feishuAppSecret.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !settings.bitableAppToken.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !settings.tableID.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        WizardPageContainer {
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .frame(width: 80, height: 80)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("同步数据 (可选)")
                .font(.title).bold()
                .frame(maxWidth: .infinity, alignment: .center)

            Text("将记账数据同步到飞书多维表格，支持多人协作与数据统计。也可以跳过，只在本地保存。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            Toggle(isOn: $settings.feishuSyncEnabled) {
                Text("同步到飞书多维表格")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onChange(of: settings.feishuSyncEnabled) { _, enabled in
                if !enabled { state.resetOnToggleOff() }
            }

            if settings.feishuSyncEnabled {
                feishuDocModeSelector
            }
        } bottomContent: {
            VStack(spacing: 10) {
                Button {
                    Task { await handleNext() }
                } label: {
                    HStack(spacing: 8) {
                        if state.isTestingFeishu {
                            ProgressView().scaleEffect(0.8).tint(.white)
                        }
                        Text("下一步")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(state.isTestingFeishu || !canProceed)

                if let result = state.feishuTestResult, !result.success {
                    wizardTestResultRow(result)
                }
            }
        }
        .onAppear {
            // 右滑返回时恢复表格链接显示
            if !settings.bitableAppToken.isEmpty && !settings.tableID.isEmpty {
                state.bitableURLInput = "https://feishu.cn/base/\(settings.bitableAppToken)?table=\(settings.tableID)"
            }
            // 右滑返回时恢复已选择的 docMode
            if state.docMode == .unselected {
                if settings.feishuAppID == kFeishuTestAppID && !settings.bitableAppToken.isEmpty {
                    state.docMode = .testDoc
                    state.createDocResult = WizardTestResult(success: true, message: "")
                } else if !settings.feishuAppID.isEmpty {
                    state.docMode = .ownDoc
                }
            }
        }
    }

    @ViewBuilder
    private var feishuDocModeSelector: some View {
        VStack(spacing: 12) {
            feishuModeButton(
                selected: state.docMode == .testDoc,
                icon: "sparkles",
                title: "使用测试多维表格",
                subtitle: "自动创建一张测试表格，仅用于测试体验"
            ) {
                state.switchToTestDoc()
            }

            feishuModeButton(
                selected: state.docMode == .ownDoc,
                icon: "key.fill",
                title: "使用我自己的飞书多维表格",
                subtitle: "需要填写 App ID / App Secret 和表格链接"
            ) {
                if state.docMode == .testDoc {
                    settings.feishuAppID     = ""
                    settings.feishuAppSecret = ""
                    settings.bitableAppToken = ""
                    settings.tableID         = ""
                    state.bitableURLInput    = ""
                }
                state.switchToOwnDoc()
            }

            if state.docMode == .testDoc { testDocContent }
            if state.docMode == .ownDoc  { ownDocContent  }
        }
    }

    @ViewBuilder
    private var testDocContent: some View {
        VStack(spacing: 12) {
            Button {
                guard state.createDocResult?.success != true else { return }
                state.createDocResult = nil
                Task { await createTestDoc() }
            } label: {
                ZStack {
                    if let result = state.createDocResult {
                        HStack(spacing: 8) {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.success ? .green : .red)
                            Text(result.success ? "已创建测试表格" : result.message)
                                .foregroundStyle(result.success ? Color.primary : Color.red)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .font(.caption)
                        }
                    } else if state.isCreatingDoc {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                            Text("正在创建表格…")
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "tablecells.badge.sparkles")
                            Text("一键创建测试表格")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(state.isCreatingDoc || state.createDocResult?.success == true)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .padding(.top, 1)
                Text("测试文档无权限保护，仅用于测试体验，请勿长期记录真实消费信息，以防数据泄露。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var ownDocContent: some View {
        VStack(spacing: 10) {
            wizardLabeledField(label: "App ID",     placeholder: "cli_...", text: $settings.feishuAppID,     isSecure: false)
            wizardLabeledField(label: "App Secret", placeholder: "密钥",   text: $settings.feishuAppSecret, isSecure: true)
            wizardLabeledField(label: "表格链接",   placeholder: "https://xxx.feishu.cn/base/...", text: $state.bitableURLInput, isSecure: false)
                .onChange(of: state.bitableURLInput) { _, newValue in parseBitableURL(newValue) }

            if let result = state.urlParseResult {
                wizardTestResultRow(result)
            }
        }
    }

    private func feishuModeButton(
        selected: Bool, icon: String, title: String, subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).fontWeight(.medium).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            )
        }
        .buttonStyle(.plain)
    }

    private func wizardLabeledField(label: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                TextField(placeholder, text: text)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func handleNext() async {
        guard state.docMode == .ownDoc && settings.isFeishuConfigured else { onNext(); return }
        state.isTestingFeishu = true
        state.feishuTestResult = nil
        defer { state.isTestingFeishu = false }
        do {
            _ = try await FeishuBitableService.shared.testConnection(
                appID: settings.feishuAppID, appSecret: settings.feishuAppSecret,
                appToken: settings.bitableAppToken, tableID: settings.tableID
            )
            onNext()
        } catch {
            state.feishuTestResult = WizardTestResult(success: false, message: "连接失败：\(error.localizedDescription)")
        }
    }

    private func createTestDoc() async {
        state.isCreatingDoc = true
        defer { state.isCreatingDoc = false }
        do {
            let (appToken, tableID) = try await FeishuBitableService.shared.createExpenseBitable(
                appID: kFeishuTestAppID, appSecret: kFeishuTestAppSecret
            )
            settings.feishuAppID     = kFeishuTestAppID
            settings.feishuAppSecret = kFeishuTestAppSecret
            settings.bitableAppToken = appToken
            settings.tableID         = tableID
            state.createDocResult = WizardTestResult(success: true, message: "")
        } catch {
            state.createDocResult = WizardTestResult(success: false, message: "创建失败: \(error.localizedDescription)")
        }
    }

    private func parseBitableURL(_ urlString: String) {
        guard let result = settings.parseBitableURL(urlString) else {
            state.urlParseResult = nil
            return
        }
        state.urlParseResult = WizardTestResult(success: result.success, message: result.message)
    }
}

// MARK: - Page 3: Member Name (原第 2 步，现移至第 3 步，飞书同步未开启时跳过)

private struct WizardMemberPage: View {
    @ObservedObject var settings: AppSettings
    let onNext: () -> Void

    var body: some View {
        WizardPageContainer {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .frame(width: 80, height: 80)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("记账成员名")
                .font(.title).bold()
                .frame(maxWidth: .infinity, alignment: .center)

            Text("多人共享一张飞书表格时，填入你的名字，方便区分是谁记录的。个人使用可不填。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            TextField("你的名字（可选）", text: $settings.userName)
                .font(.body)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } bottomContent: {
            Button("下一步") { onNext() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

// MARK: - Page 4: Action Button Guide

private struct WizardActionButtonPage: View {
    let onDone: () -> Void

    private let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/925b64d4982e4559a061f8bfb920913d")!

    private let guideSteps = [
        "点击上方「获取快捷指令」，在快捷指令 App 中完成添加",
        "进入「设置 → 操作按钮」→ 选择「快捷指令」→ 选择「立即记账」"
    ]

    var body: some View {
        WizardPageContainer {
            Image(systemName: "record.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .frame(width: 80, height: 80)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("配置 Action Button")
                .font(.title).bold()
                .frame(maxWidth: .infinity, alignment: .center)

            Text("按下方步骤添加快捷指令并绑定到 Action Button，之后按一下就能自动记账。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            // 获取快捷指令链接
            Link(destination: shortcutURL) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("获取快捷指令")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(guideSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption).fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.accentColor))
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } bottomContent: {
            Button("完成") { onDone() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

// MARK: - Shared Utilities

private struct WizardTestResult {
    let success: Bool
    let message: String
}

private func wizardTestResultRow(_ result: WizardTestResult) -> some View {
    HStack {
        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(result.success ? .green : .red)
        Text(result.message)
            .font(.caption)
            .foregroundStyle(result.success ? .green : .red)
    }
}

// MARK: - Preview

#Preview {
    SetupWizardView()
        .environmentObject(AppSettings())
}
