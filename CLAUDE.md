# Plutus

iOS 截图自动记账 App。Action Button 触发 Shortcuts → GLM Vision 识别消费信息 → 写入飞书多维表格。

## 项目信息

- **平台**：iOS 17.0+，Swift 5.9，SwiftUI
- **构建**：XcodeGen（`project.yml` → `.xcodeproj`，新增 Swift 文件后必须运行 `xcodegen generate`）
- **AI**：智谱 GLM `glm-4v-flash`，prompt 维护在 `GLMVisionService.analyzeCore/Detail()`
- **后端**：飞书 Bitable（`tenant_access_token`，2h 有效期，提前 5min 自动刷新）

## 目录结构

```
ExpenseCapture/
├── App/          # UI：ContentView(TabBar) / SettingsView / RecordsView / LogView
├── Intents/      # AnalyzeExpenseIntent — Shortcuts 入口，两阶段识别主流程
├── Services/     # GLMVisionService / FeishuBitableService
├── Models/       # ExpenseRecord（CoreExtraction + DetailExtraction）
└── Storage/      # AppSettings(@AppStorage) / IntentLogger / ExpenseRecordStore
```

## 核心流程

**两阶段识别**：
1. **Phase 1**（用户等待）：`analyzeCore()` → `addRecord()` 返回 `record_id` → 弹出 dialog → `perform()` 返回
2. **Phase 2**（fire-and-forget `Task {}`）：`analyzeDetail()` → `updateRecord()` PATCH 飞书 + 更新本地

**分类体系**：二级分类（32类）由 GLM 识别；一级分类（9类）由 `primaryCategory(from:)` 本地推导，无需 AI。

## 关键约束

**App Intents**
- `perform()` 必须在 Phase 1 完成后立即返回，Phase 2 用 `Task {}` 异步启动（Shortcuts 有超时）
- Phase 1 失败 → 抛错误 dialog 给用户；Phase 2 失败 → 只写 log，不影响已返回的 dialog

**GLM Prompt**
- prompt 直接在 `GLMVisionService.swift` 内维护；修改后需确保 JSON 解析结构不 break
- `CoreExtraction`（amount/merchant/transactionDate）和 `DetailExtraction`（subCategory/notes）是解析契约

**飞书 API**
- DateTime 字段必须传毫秒时间戳（非字符串），解析失败 fallback 当前时间
- 字段名通过 `AppSettings.field*` 映射，不要硬编码中文字段名

**图片处理**
- 压缩必须放在 `Task.detached(priority: .userInitiated)`（不继承 actor context，避免阻塞主线程）
- 最大 1024px / 1MB，勿降至 512px（准确率会显著下降）

**存储**
- 只用 `UserDefaults`（`@AppStorage` + 手动 JSON encode），不引入 CoreData/SwiftData

**Info.plist**
- 自定义 plist key 必须写在 `project.yml` 的 `info.properties`，不要直接编辑 `Info.plist`

## CHANGELOG 规则

每次修改 `**/*.swift`、`Assets.xcassets/` 或 `project.yml` 后，**commit 前**自动更新 `CHANGELOG.md`：

```markdown
## vX.Y.Z — 简短标题
**日期**：YYYY-MM

### 变更内容
- 面向产品描述（做了什么 + 解决了什么问题）
```

版本号递增规则：patch（v0.13.0 → v0.14.0）。

## Git 约定

- Conventional commits 格式
- 不 commit：`xcuserdata/`、`UserInterfaceState.xcuserstate`、API Key
